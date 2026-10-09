import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart' as dio;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../services/image_processor.dart';
import '../services/api_service.dart';
import '../services/pending_grade_sync_service.dart';
import '../services/cv/qr_classification_service.dart';
import '../services/cv/camera_frame_service.dart';
import '../services/cv/live_scan_policy.dart';
import '../services/supabase_service.dart';
import '../services/deep_link_service.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/qr_data.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../models/omr/templates/standard_50_questions.dart';
import '../utils/ui_utils.dart';
import 'sheet_evaluation_screen.dart';
import 'developer_evaluation_tools_screen.dart';
import '../config/app_build.dart';
import '../services/developer_template_store.dart';

/// Screen responsible for live camera feed and document edge detection.
/// Enforces:
/// - BR-06: Local Edge OMR Processing (Isolate-based).
/// - BR-04: Student ID recognition.
class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final bool isActive;
  final VoidCallback? onClose;
  final bool developerSandbox;
  final BubbleSheetTemplate? sandboxTemplate;
  const ScannerScreen({
    super.key,
    required this.cameras,
    required this.isActive,
    this.onClose,
    this.developerSandbox = false,
    this.sandboxTemplate,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isOmrProcessing = false;
  bool _paperDetected = false;
  bool _isFlashOn = false;

  // Course Invitation Confirmation Card State
  bool _isConfirmationCardOpen = false;
  String? _lastScannedInviteCode;
  DateTime? _lastInvitePromptTime;

  bool get _developerSandbox =>
      AppBuild.developerTools && widget.developerSandbox;

  bool get _isProcessing => _isOmrProcessing || _isConfirmationCardOpen;

  bool get _canCapturePaper =>
      !_isProcessing &&
      _controller != null &&
      _controller!.value.isInitialized &&
      (_developerSandbox ||
          (_lockedSheetQr != null &&
              _validatedSheetQr == _lockedSheetQr!.sheetIdentifier));

  int get _frameRotationDegrees {
    final controller = _controller;
    if (controller == null) return 0;
    return CameraFrameService.rotationDegrees(
      sensorOrientation: controller.description.sensorOrientation,
      orientation: controller.value.lockedCaptureOrientation ??
          controller.value.deviceOrientation,
      lensDirection: controller.description.lensDirection,
      isIOS: Platform.isIOS,
    );
  }

  // Isolate state
  bool _isIsolateWorking = false;

  final _detectedCorners = ValueNotifier<List<Offset>?>(null);
  Timer? _overlayExpiry;
  List<double>? _rawCorners;
  QrData?
      _lockedSheetQr; // BR-05: Lock the decoded QR so it isn't lost during edge detection
  String? _validatedSheetQr;
  int _qrValidationRevision = 0;
  String? _rejectedQrId;
  DateTime? _rejectedQrAt;
  String _lastQrDebugText = 'QR: waiting';
  Offset? _focusPoint;

  // Locally evaluated sheets are queued as JSON, then synced independently.
  int _pendingSyncCount = 0;
  bool _isSyncingPending = false;
  final Set<String> _processedSheetIds = {};

  Isolate? _isolate;
  bool _isolateStarting = false;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  StreamSubscription<dynamic>? _isolateSubscription;
  BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  Future<void>? _qrDecodeFuture;
  bool _qrDecodeInFlight = false;
  int _qrSession = 0;
  DateTime? _lastQrScanTime;
  DateTime? _lastFrameTime;
  DateTime? _qrLockTime;

  @override
  void initState() {
    super.initState();
    _isolateSubscription = _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is ScanResponse) {
        if (message.scanSession != _qrSession) return;
        // A response can arrive while the review screen is open. Release the
        // in-flight frame lock even when that stale response is discarded.
        _isIsolateWorking = false;
        if (mounted && !_isProcessing) _handleLiveResponse(message);
      } else if (message is ProcessedSheet && mounted) {
        _handleProcessedSheet(message);
      }
    });
    if (!_developerSandbox) {
      unawaited(_restoreAndSyncPending());
    } else {
      _lastQrDebugText = 'Local test capture • no sign-in required';
    }
    if (widget.isActive) _startCapture();
  }

  Future<void> _restoreAndSyncPending() async {
    try {
      final queued = await PendingGradeSyncService.pending();
      _processedSheetIds
          .addAll(queued.map((e) => e['result']['sheet_id'].toString()));
      if (mounted) setState(() => _pendingSyncCount = queued.length);
      await _retryPending();
    } catch (error) {
      debugPrint('Could not restore pending grade sync: $error');
    }
  }

  Future<void> _retryPending() async {
    if (_isSyncingPending) return;
    if (mounted) setState(() => _isSyncingPending = true);
    try {
      await PendingGradeSyncService.syncPending();
      final remaining = await PendingGradeSyncService.pending();
      if (mounted) setState(() => _pendingSyncCount = remaining.length);
    } catch (error) {
      debugPrint('Could not sync pending grades: $error');
    } finally {
      if (mounted) setState(() => _isSyncingPending = false);
    }
  }

  void _startCapture() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _startIsolate();
    _initializeCamera();
  }

  @override
  void didUpdateWidget(ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _startCapture();
      } else {
        _resetDetectionForNextSheet();
        _disposeCameraAndRestore();
      }
    }
  }

  Future<void> _disposeCameraOnly() async {
    _overlayExpiry?.cancel();
    if (_controller == null) return;
    final controller = _controller!;
    _controller = null;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.setFlashMode(FlashMode.off);
      await controller.dispose();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _paperDetected = false;
        _isFlashOn = false;
        _isOmrProcessing = false;
        _isConfirmationCardOpen = false;
      });
    }
  }

  Future<void> _disposeCameraAndRestore() async {
    await _disposeCameraOnly();
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    _isolate?.kill();
    _isolate = null;
    _isolateSendPort = null;
    _isIsolateWorking = false;
  }

  /// Offloads heavy CV processing to a separate Isolate to prevent UI jank.
  Future<void> _startIsolate() async {
    if (_isolate != null || _isolateStarting) return;
    _isolateStarting = true;
    try {
      final isolate = await Isolate.spawn(
          ImageProcessor.edgeDetectionWorker, _mainReceivePort.sendPort);
      if (!mounted || !widget.isActive) {
        isolate.kill();
      } else {
        _isolate = isolate;
      }
    } finally {
      _isolateStarting = false;
    }
  }

  String _sheetCheckError(Object error) {
    if (error is StateError &&
        error.message.toString().contains('Sign in to evaluate')) {
      return 'Sign in to evaluate this paper.';
    }
    if (error is dio.DioException) {
      switch (error.response?.statusCode) {
        case 401:
          return 'Sign in to evaluate this paper.';
        case 403:
          return 'You cannot evaluate this paper. Only its course instructor can scan it.';
        case 404:
          return 'This answer sheet was not found. Check its QR code.';
        case 422:
          return 'This paper has an invalid answer-sheet QR code.';
      }
    }
    if (error is FormatException) {
      return 'This paper has an invalid answer-sheet QR code.';
    }
    return 'Could not verify this paper. Check your connection and try again.';
  }

  void _rejectSheetQr(String identifier, String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final showPrompt = _rejectedQrId != identifier ||
        _rejectedQrAt == null ||
        now.difference(_rejectedQrAt!) > const Duration(seconds: 15);
    _rejectedQrId = identifier;
    if (showPrompt) _rejectedQrAt = now;
    _qrValidationRevision++;
    setState(() {
      _lockedSheetQr = null;
      _validatedSheetQr = null;
      _qrLockTime = null;
      _lastQrDebugText = message;
    });
    if (showPrompt) _showErrorSnackBar(message);
  }

  void _tryLockSheetQr(QrData candidate) {
    if (!mounted ||
        !widget.isActive ||
        _isProcessing ||
        _lockedSheetQr != null) {
      return;
    }
    final identifier = candidate.sheetIdentifier;
    if (identifier.isEmpty || identifier == 'UNKNOWN') return;
    if (_processedSheetIds.contains(identifier)) {
      _rejectSheetQr(identifier,
          'This paper has already been scanned. Try another paper.');
      return;
    }
    if (_rejectedQrId == identifier &&
        _rejectedQrAt != null &&
        DateTime.now().difference(_rejectedQrAt!) <
            const Duration(seconds: 15)) {
      return;
    }
    setState(() {
      _lockedSheetQr = candidate;
      _validatedSheetQr = null;
      _qrLockTime = DateTime.now();
      _lastQrDebugText = 'Checking: $identifier';
    });
    final revision = ++_qrValidationRevision;
    unawaited(_checkLockedSheetQr(identifier, _qrSession, revision));
  }

  Future<void> _checkLockedSheetQr(
      String identifier, int scanSession, int revision) async {
    try {
      final scanned = await ApiService.checkSheetScanned(identifier);
      if (!mounted ||
          !widget.isActive ||
          scanSession != _qrSession ||
          revision != _qrValidationRevision ||
          _lockedSheetQr?.sheetIdentifier != identifier) {
        return;
      }
      if (scanned) {
        _rejectSheetQr(identifier,
            'This paper has already been scanned. Try another paper.');
      } else {
        setState(() {
          _validatedSheetQr = identifier;
          _lastQrDebugText = 'Ready: $identifier';
        });
      }
    } catch (error) {
      if (mounted &&
          widget.isActive &&
          scanSession == _qrSession &&
          revision == _qrValidationRevision &&
          _lockedSheetQr?.sheetIdentifier == identifier) {
        _rejectSheetQr(identifier, _sheetCheckError(error));
      }
    }
  }

  void _handleLiveResponse(ScanResponse message) {
    // 1. Detect whether the current frame contains a Course Invitation QR
    final inviteCode = message.detectedQr == null
        ? null
        : QrClassificationService.extractInvitationCodeFromQr(
            message.detectedQr!);

    final isCourseInvite = inviteCode != null;

    if (isCourseInvite) {
      // SUPPRESS PAPER DETECTION: This is a Course Invitation QR, NOT an OMR Answer Sheet!
      _clearLiveOverlay();
      _lastQrDebugText = DeepLinkService.isInviteToken(inviteCode)
          ? 'QR: private course invitation'
          : 'QR: course code';

      _lockedSheetQr = null;
      _validatedSheetQr = null;
      _qrLockTime = null;

      // IMMEDIATELY prompt the "Join Course" confirmation card
      if (!_isConfirmationCardOpen && !_isProcessing) {
        _triggerCourseJoinPrompt(inviteCode);
      }

      return; // Do NOT proceed to OMR paper edge detection
    }

    // --- Standard OMR Answer Sheet Detection Path ---

    // Keep QR tracking active even before full paper-edge confirmation so valid answer-sheet
    // QR codes are not suppressed by the edge-detection gate.
    final candidateQr = message.detectedQr;

    // If we haven't locked a sheet QR yet, keep looking for one
    if (!_developerSandbox && _lockedSheetQr == null) {
      if (candidateQr != null &&
          candidateQr.sheetIdentifier.isNotEmpty &&
          candidateQr.sheetIdentifier != 'UNKNOWN') {
        final inviteCode =
            QrClassificationService.extractInvitationCodeFromQr(candidateQr);
        if (inviteCode == null) {
          _tryLockSheetQr(candidateQr);
        } else {
          _lastQrDebugText = DeepLinkService.isInviteToken(inviteCode)
              ? 'QR: private invitation candidate'
              : 'QR: course code candidate';
        }
      } else {
        _lastQrDebugText = 'QR: waiting';
      }
    }

    // Every completed fresh frame updates only the overlay subtree. Never keep
    // an old polygon floating over a moving preview after a miss or timeout.
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    if (!message.foundPaper ||
        message.corners?.length != 8 ||
        !LiveScanPolicy.isFresh(message.capturedAtMicros, nowMicros)) {
      _clearLiveOverlay();
      return;
    }
    _rawCorners = message.corners;
    _detectedCorners.value = List.generate(
        4, (i) => Offset(message.corners![i * 2], message.corners![i * 2 + 1]));
    if (!_paperDetected) setState(() => _paperDetected = true);
    _overlayExpiry?.cancel();
    final remainingMicros = LiveScanPolicy.maxOverlayAge.inMicroseconds -
        (nowMicros - message.capturedAtMicros);
    _overlayExpiry =
        Timer(Duration(microseconds: remainingMicros), _clearLiveOverlay);
  }

  void _clearLiveOverlay() {
    _overlayExpiry?.cancel();
    _overlayExpiry = null;
    _rawCorners = null;
    _detectedCorners.value = null;
    if (mounted && _paperDetected) setState(() => _paperDetected = false);
  }

  String _normalizeJoinCode(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim().toUpperCase();
  }

  Future<void> _joinCourseFromPrompt(
      String inviteCode, BuildContext bottomSheetContext) async {
    final normalizedCode = _normalizeJoinCode(inviteCode);
    final isPrivateInvite = DeepLinkService.isInviteToken(inviteCode);
    debugPrint('JOIN COURSE BUTTON: privateInvite=$isPrivateInvite');

    var progressDialogOpen = true;
    showDialog<void>(
      context: bottomSheetContext,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Joining course...')),
          ],
        ),
      ),
    );
    try {
      final join = isPrivateInvite
          ? SupabaseService.joinCourseWithInvitation(normalizedCode)
          : SupabaseService.joinClass(normalizedCode);
      final course = await join.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
          'Joining the course timed out. Check your connection and try again.',
        ),
      );

      if (mounted) {
        _isConfirmationCardOpen = false;
      }

      if (progressDialogOpen && bottomSheetContext.mounted) {
        Navigator.of(bottomSheetContext, rootNavigator: true).pop();
        progressDialogOpen = false;
      }
      if (bottomSheetContext.mounted &&
          Navigator.of(bottomSheetContext, rootNavigator: true).canPop()) {
        Navigator.of(bottomSheetContext, rootNavigator: true).pop();
      }

      debugPrint('JOIN COURSE: success -> ${course.name}');
      DeepLinkService.notifyCourseJoined(course);
      final targetContext = navigatorKey.currentContext ?? context;
      if (targetContext.mounted) {
        CheckMateUi.showTopPrompt(
          targetContext,
          'Joined course: ${course.name}!',
          isError: false,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('JOIN COURSE: failed privateInvite=$isPrivateInvite :: $e');
      debugPrintStack(stackTrace: stackTrace, label: 'Course join failure');
      if (progressDialogOpen && bottomSheetContext.mounted) {
        Navigator.of(bottomSheetContext, rootNavigator: true).pop();
        progressDialogOpen = false;
      }
      if (bottomSheetContext.mounted) {
        final message =
            e.toString().replaceFirst(RegExp(r'^(Exception|Error): '), '');
        await showDialog<void>(
          context: bottomSheetContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could not join course'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _triggerCourseJoinPrompt(String inviteCode) async {
    if (_isConfirmationCardOpen || !mounted) return;

    // Debounce duplicate scans of same code within 3 seconds
    if (_lastScannedInviteCode == inviteCode &&
        _lastInvitePromptTime != null &&
        DateTime.now().difference(_lastInvitePromptTime!).inMilliseconds <
            1000) {
      return;
    }

    // Synchronously lock state immediately to prevent live camera stream race conditions
    _isConfirmationCardOpen = true;
    _lastScannedInviteCode = inviteCode;
    _lastInvitePromptTime = DateTime.now();

    final normalizedInviteCode = _normalizeJoinCode(inviteCode);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.school_rounded, color: accentColor, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Course Invitation Detected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DeepLinkService.isInviteToken(inviteCode)
                    ? 'Private course invitation'
                    : 'Course Code: $normalizedInviteCode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Would you like to enroll in this course directly?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (mounted) {
                          _isConfirmationCardOpen = false;
                        }
                        if (Navigator.of(bottomSheetContext,
                                rootNavigator: true)
                            .canPop()) {
                          Navigator.of(bottomSheetContext, rootNavigator: true)
                              .pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white30 : Colors.grey.shade400,
                        ),
                      ),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _joinCourseFromPrompt(
                            inviteCode, bottomSheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'JOIN COURSE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (mounted) {
      _isConfirmationCardOpen = false;
    }
  }

  /// BR-05 Enforcement: Resolve Sheet ID via backend before grading.
  Future<void> _handleProcessedSheet(ProcessedSheet sheet,
      {Map<String, dynamic>? preResolvedMetadata,
      BubbleSheetTemplate? processingTemplate}) async {
    var queued = false;
    try {
      if (_developerSandbox) {
        await Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) => DeveloperEvaluationToolsScreen(
                    sheet: sheet,
                    template: AnswerSheetTemplateRegistry.byId(
                            sheet.templateId ?? '') ??
                        processingTemplate ??
                        widget.sandboxTemplate ??
                        Standard50QuestionsTemplate())));
        return;
      }
      final qrData = sheet.qrData;
      final rawIdentifier = qrData?.sheetIdentifier ?? '';

      // 1. FIRST: Detect whether this QR is actually a Course Invitation.
      final inviteCode = qrData == null
          ? null
          : QrClassificationService.extractInvitationCodeFromQr(qrData);
      if (inviteCode != null) {
        await _triggerCourseJoinPrompt(inviteCode);
        return;
      }

      // 2. SECOND: Validate if this is a valid OMR Answer Sheet QR.
      if (qrData == null ||
          rawIdentifier.isEmpty ||
          rawIdentifier == "UNKNOWN") {
        _showErrorSnackBar("Invalid paper, please try again.");
        return;
      }

      // 3. Prevent duplicates in same session and in database
      if (_processedSheetIds.contains(rawIdentifier)) {
        _showErrorSnackBar(
            "This paper has already been scanned. Try another paper.");
        return;
      }

      final isAlreadyScanned =
          await ApiService.checkSheetScanned(rawIdentifier);
      if (isAlreadyScanned) {
        _showErrorSnackBar(
            "This paper has already been scanned. Try another paper.");
        return;
      }

      // 4. Resolve metadata from Supabase
      // This verifies if the sheet actually belongs to this exam/student
      final metadata =
          preResolvedMetadata ?? await ApiService.resolveSheet(rawIdentifier);
      final studentName = metadata['student_name'] ??
          metadata['profiles']?['name'] ??
          'Student';

      if (mounted) {
        _processedSheetIds.add(rawIdentifier);

        // Turn off flash torch before navigating to evaluation screen so the flash LED doesn't stay burning
        if (_controller != null) {
          try {
            await _controller!.setFlashMode(FlashMode.off);
            if (mounted) setState(() => _isFlashOn = false);
          } catch (_) {}
        }

        if (!mounted) return;

        final resolvedExamId = metadata['exam_id']?.toString() ??
            metadata['exams']?['id']?.toString();
        if (resolvedExamId == null || resolvedExamId.isEmpty) {
          throw StateError('The sheet did not resolve to an assessment.');
        }

        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) => SheetEvaluationScreen(
              sheet: sheet,
              metadata: metadata,
              loadQuestions: SupabaseService.getExamQuestions,
              developerToolsBuilder: AppBuild.developerTools
                  ? (_) => DeveloperEvaluationToolsScreen(
                        sheet: sheet,
                        template: AnswerSheetTemplateRegistry.byId(
                                sheet.templateId ?? '') ??
                            processingTemplate ??
                            AnswerSheetTemplateRegistry.all.firstWhere(
                                (t) => t.name == sheet.templateName,
                                orElse: () => AnswerSheetTemplateRegistry
                                    .forQuestionCount(sheet.questionCapacity ??
                                        sheet.results.length)),
                        loadQuestions: () =>
                            SupabaseService.getExamQuestions(resolvedExamId),
                      )
                  : null,
              onEvaluated: (evaluatedSheet) async {
                if (queued) return;
                final updatedSheet = evaluatedSheet.copyWith(
                  qrData: QrData(
                    studentName: studentName,
                    examCode: resolvedExamId,
                    course:
                        metadata['exams']?['classes']?['name']?.toString() ??
                            sheet.qrData?.course ??
                            '',
                    examTitle: metadata['exams']?['title']?.toString() ??
                        sheet.qrData?.examTitle ??
                        '',
                    sheetIdentifier: rawIdentifier,
                    templateName: sheet.qrData?.templateName,
                  ),
                );
                // Queue the immutable deterministic evaluation before showing
                // success. Each sheet uses its own resolved assessment ID.
                await PendingGradeSyncService.enqueue(
                  examId: resolvedExamId,
                  result: updatedSheet.toSyncResult(),
                );
                queued = true;
                if (mounted) setState(() => _pendingSyncCount++);
                unawaited(_retryPending());
              },
            ),
          ),
        );

        if (!queued) {
          _processedSheetIds.remove(rawIdentifier);
        } else if (mounted) {
          _showSuccessSnackBar(
              'Result queued for $studentName. Ready for the next sheet.');
        }
      }
    } catch (e) {
      if (!queued) _processedSheetIds.remove(sheet.qrData?.sheetIdentifier);
      if (mounted) {
        _showErrorSnackBar(_sheetCheckError(e));
      }
    } finally {
      // Capture owns the reset when it invoked this review flow.
      if (!_isOmrProcessing) _resetDetectionForNextSheet();
    }
  }

  void _resetDetectionForNextSheet() {
    if (!mounted) return;
    final oldScanner = _barcodeScanner;
    final oldDecode = _qrDecodeFuture;
    _qrSession++;
    _qrValidationRevision++;
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    _qrDecodeFuture = null;
    _qrDecodeInFlight = false;
    // Keep the previous native decoder alive until its in-flight frame ends.
    // A bounded wait also releases it if the platform call never returns.
    unawaited(() async {
      try {
        await Future.any<void>([
          oldDecode ?? Future<void>.value(),
          Future<void>.delayed(const Duration(seconds: 2)),
        ]);
        await oldScanner.close();
      } catch (error) {
        debugPrint('Could not close previous QR decoder: $error');
      }
    }());
    _isIsolateWorking = false;
    _lastFrameTime = null;
    _lastQrScanTime = null;
    _overlayExpiry?.cancel();
    setState(() {
      _isOmrProcessing = false;
      _lockedSheetQr = null;
      _validatedSheetQr = null;
      _detectedCorners.value = null;
      _rawCorners = null;
      _qrLockTime = null;
      _paperDetected = false;
      _lastQrDebugText = _developerSandbox
          ? 'Local test capture • no sign-in required'
          : 'Ready for next sheet';
    });
  }

  void _showErrorSnackBar(String msg) {
    CheckMateUi.showTopPrompt(context, msg);
  }

  void _showSuccessSnackBar(String msg) {
    CheckMateUi.showTopPrompt(context, msg, isError: false);
  }

  void _onCameraFrame(CameraImage image) {
    if (!mounted || _isProcessing) return;

    // QR reads must not depend on how long paper-edge processing takes.
    if (!_developerSandbox && !_qrDecodeInFlight) {
      final session = _qrSession;
      final scanner = _barcodeScanner;
      _qrDecodeInFlight = true;
      final decode = _tryDecodeQrFromCameraFrame(image, scanner, session);
      _qrDecodeFuture = decode;
      unawaited(decode.whenComplete(() {
        if (_qrSession == session) {
          _qrDecodeInFlight = false;
          _qrDecodeFuture = null;
        }
      }));
    }
    if (_isolateSendPort == null || _isIsolateWorking) return;

    // At most one current frame is in flight; busy frames are dropped rather
    // than queued. The lighter marker tracker can follow up to camera cadence.
    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!) < LiveScanPolicy.frameInterval) {
      return;
    }
    _lastFrameTime = now;

    // Auto-unlock QR lock if idle for over 20 seconds without completing capture
    if (_lockedSheetQr != null &&
        _qrLockTime != null &&
        now.difference(_qrLockTime!).inSeconds > 20) {
      if (mounted) {
        setState(() {
          _lockedSheetQr = null;
          _validatedSheetQr = null;
          _qrValidationRevision++;
          _qrLockTime = null;
          _lastQrDebugText = 'QR lock expired, rescan sheet';
        });
      }
    }

    _isIsolateWorking = true;
    try {
      _isolateSendPort!.send(ScanRequest(
        bytes: image.planes[0].bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: image.planes[0].bytesPerRow,
        bytesPerPixel: image.format.group == ImageFormatGroup.bgra8888 ? 4 : 1,
        rotationIndex: _frameRotationDegrees ~/ 90,
        replyPort: _mainReceivePort.sendPort,
        scanSession: _qrSession,
        capturedAtMicros: now.microsecondsSinceEpoch,
        detectQr: !_developerSandbox &&
            (image.planes.length != 1 ||
                (Platform.isAndroid &&
                    InputImageFormatValue.fromRawValue(image.format.raw) !=
                        InputImageFormat.nv21) ||
                (Platform.isIOS &&
                    InputImageFormatValue.fromRawValue(image.format.raw) !=
                        InputImageFormat.bgra8888)),
      ));
    } catch (e) {
      _isIsolateWorking = false;
      debugPrint("ScanRequest send notice: $e");
    }
  }

  Future<void> _initializeCamera() async {
    List<CameraDescription> cams = widget.cameras;
    if (cams.isEmpty) {
      try {
        cams = await availableCameras();
      } catch (e) {
        debugPrint("Camera fallback fetch error: $e");
      }
    }
    if (cams.isEmpty) return;

    _controller = CameraController(
      cams.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first),
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      // Lock the native stream and still capture together. Locking only the
      // screen leaves camera buffers free to change orientation as it tilts.
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      await _controller!.startImageStream(_onCameraFrame);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isFlashOn = false;
        });
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  Future<void> _handleTapToFocus(
      TapDownDetails details, Size widgetSize) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final offset = details.localPosition;
    setState(() => _focusPoint = offset);
    try {
      // The camera plugin already transforms preview coordinates to the
      // sensor. Rotating here focuses a different region of a close sheet.
      final nx = offset.dx / widgetSize.width;
      final ny = offset.dy / widgetSize.height;
      await _controller!
          .setFocusPoint(Offset(nx.clamp(0.05, 0.95), ny.clamp(0.05, 0.95)));
      await _controller!
          .setExposurePoint(Offset(nx.clamp(0.05, 0.95), ny.clamp(0.05, 0.95)));
    } catch (_) {
      // Some cameras do not support setting an exposure point.
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted && _focusPoint == offset) {
        setState(() => _focusPoint = null);
      }
    }
  }

  Future<void> _tryDecodeQrFromCameraFrame(
      CameraImage image, BarcodeScanner scanner, int session) async {
    final now = DateTime.now();
    if (_lastQrScanTime != null &&
        now.difference(_lastQrScanTime!).inMilliseconds < 250) {
      return;
    }
    _lastQrScanTime = now;

    try {
      final inputFormat = InputImageFormatValue.fromRawValue(image.format.raw);
      if (image.planes.length != 1 ||
          (Platform.isAndroid && inputFormat != InputImageFormat.nv21) ||
          (Platform.isIOS && inputFormat != InputImageFormat.bgra8888) ||
          inputFormat == null) {
        return;
      }
      // NV21 and BGRA each arrive in one plane. Concatenating arbitrary YUV
      // planes does not produce NV21 and can give the native decoder bad data.
      final plane = image.planes.single;
      final bytes = plane.bytes;
      final bytesPerRow = plane.bytesPerRow;
      final requiredLength = Platform.isAndroid
          ? image.width * image.height * 3 ~/ 2
          : bytesPerRow * image.height;
      if (bytes.length < requiredLength) return;
      final rotationDegrees = _frameRotationDegrees;
      final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
      if (rotation == null) return;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: inputFormat,
          bytesPerRow: bytesPerRow,
        ),
      );

      final barcodes = await scanner.processImage(inputImage);
      if (!mounted ||
          _isProcessing ||
          session != _qrSession ||
          barcodes.isEmpty) {
        return;
      }

      final rawValue = barcodes.first.rawValue ?? '';
      if (rawValue.trim().isEmpty) {
        return;
      }

      final candidate = QrData.fromRaw(rawValue);
      if (candidate.sheetIdentifier.isEmpty ||
          candidate.sheetIdentifier == 'UNKNOWN') {
        return;
      }

      final inviteCode =
          QrClassificationService.extractInvitationCodeFromQr(candidate);
      if (inviteCode != null) {
        _lastQrDebugText = DeepLinkService.isInviteToken(inviteCode)
            ? 'QR: private invitation candidate'
            : 'QR: course code candidate';
        if (mounted) {
          await _triggerCourseJoinPrompt(inviteCode);
        }
        return;
      }

      // If we haven't locked a QR yet, lock it from the camera frame if not already confirmed!
      if (_lockedSheetQr == null && mounted && session == _qrSession) {
        _tryLockSheetQr(candidate);
      }
    } catch (e) {
      debugPrint('QR decode failed: $e');
    }
  }

  @override
  void dispose() {
    _disposeCameraAndRestore();
    _isolateSubscription?.cancel();
    _mainReceivePort.close();
    _barcodeScanner.close();
    _overlayExpiry?.cancel();
    _detectedCorners.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: CircularProgressIndicator(color: Colors.blueAccent)));
    }
    final size = MediaQuery.of(context).size;
    final safePadding = MediaQuery.paddingOf(context);
    final cameraValue = _controller!.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellowAccent : Colors.blueAccent;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.width * cameraValue.aspectRatio,
              child: AspectRatio(
                aspectRatio: 1 / cameraValue.aspectRatio,
                child: LayoutBuilder(builder: (context, constraints) {
                  final widgetSize = constraints.biggest;
                  return Stack(children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _handleTapToFocus(d, widgetSize),
                      child: CameraPreview(_controller!),
                    ),
                    if (_focusPoint != null)
                      Positioned(
                          left: _focusPoint!.dx - 30,
                          top: _focusPoint!.dy - 30,
                          child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: accentColor, width: 1.5)))),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<List<Offset>?>(
                          valueListenable: _detectedCorners,
                          builder: (context, corners, _) => corners == null
                              ? const SizedBox.shrink()
                              : CustomPaint(
                                  painter: EdgePainter(
                                      corners: corners,
                                      isDetected: true,
                                      color: accentColor)),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),

          if (_isOmrProcessing)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        _developerSandbox
                            ? 'PREPARING TEST PREVIEW...'
                            : 'IDENTIFYING STUDENT...',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                        _developerSandbox
                            ? 'Reading this test sheet locally...'
                            : 'Resolving answer key & running local OMR...',
                        style: TextStyle(
                            color: Colors.grey.shade300, fontSize: 13)),
                  ],
                ),
              ),
            ),

          Positioned(
            top: safePadding.top + 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                Expanded(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    _lastQrDebugText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                )),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!.call();
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
                ),
              ],
            ),
          ),

          // Flash button on top left
          Positioned(
            top: safePadding.top + 66,
            left: 12,
            child: FloatingActionButton.small(
              heroTag: 'flash',
              onPressed: () async {
                final nextMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
                await _controller?.setFlashMode(nextMode);
                setState(() => _isFlashOn = !_isFlashOn);
              },
              backgroundColor: Colors.black45,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white),
            ),
          ),

          Positioned(
            bottom: safePadding.bottom + 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_pendingSyncCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      onPressed: _isSyncingPending ? null : _retryPending,
                      icon: Icon(
                          _isSyncingPending ? Icons.sync : Icons.cloud_upload),
                      label: Text(_isSyncingPending
                          ? 'Syncing saved sheets…'
                          : 'Retry sync ($_pendingSyncCount pending)'),
                    ),
                  ),
                if (_paperDetected && !_isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(30)),
                      child: const Text("PAPER DETECTED",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                  ),
                if (_canCapturePaper)
                  const Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: 14),
                    child: Text(
                      'Keep all four corner circles visible. Tap the sheet to focus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: FloatingActionButton(
                        heroTag: 'capture',
                        onPressed: _canCapturePaper ? _captureAndProcess : null,
                        backgroundColor:
                            _canCapturePaper ? accentColor : Colors.white24,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40)),
                        child: const Icon(Icons.qr_code_scanner,
                            color: Colors.black, size: 40),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resumeCameraStream() async {
    if (!mounted || !widget.isActive) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      await _startIsolate();
      if (mounted && widget.isActive) await _initializeCamera();
      return;
    }
    try {
      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }
      if (!mounted || !widget.isActive || _controller != controller) return;
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_onCameraFrame);
      }
    } catch (error) {
      debugPrint('Could not resume scanner stream: $error');
      if (!mounted || !widget.isActive || _controller != controller) return;
      await _disposeCameraOnly();
      if (mounted && widget.isActive) {
        await _startIsolate();
        await _initializeCamera();
      }
    }
  }

  Future<void> _captureAndProcess() async {
    if (!_canCapturePaper) {
      final inviteCode = _lockedSheetQr == null
          ? null
          : QrClassificationService.extractInvitationCodeFromQr(
              _lockedSheetQr!);
      if (inviteCode != null) {
        _isConfirmationCardOpen = false;
        await _triggerCourseJoinPrompt(inviteCode);
        return;
      }
      _showErrorSnackBar(
          'Show the answer-sheet QR code and wait for it to be verified.');
      return;
    }

    final corners =
        _rawCorners != null ? List<double>.from(_rawCorners!) : <double>[];
    setState(() => _isOmrProcessing = true);

    try {
      // Pause live stream before taking photo to prevent Camera HAL lock/crash on Android
      if (_controller != null && _controller!.value.isStreamingImages) {
        try {
          await _controller!.stopImageStream();
        } catch (e) {
          debugPrint("Notice: stopImageStream before capture: $e");
        }
      }

      final XFile photo = await _controller!.takePicture();
      try {
        await _controller!.pausePreview();
      } catch (e) {
        debugPrint("Notice: pausePreview: $e");
      }
      final Uint8List bytes = await photo.readAsBytes();

      // 1. Dynamically resolve the template from metadata or question count before processing OMR
      BubbleSheetTemplate resolvedTemplate = _developerSandbox
          ? (widget.sandboxTemplate ?? Standard50QuestionsTemplate())
          : Standard50QuestionsTemplate();
      Map<String, dynamic>? preResolvedMetadata;

      final rawIdentifier = _lockedSheetQr?.sheetIdentifier ?? '';
      if (rawIdentifier.isNotEmpty && rawIdentifier != 'UNKNOWN') {
        bool isAlreadyScanned;
        try {
          isAlreadyScanned = await ApiService.checkSheetScanned(rawIdentifier);
        } catch (error) {
          if (mounted) _showErrorSnackBar(_sheetCheckError(error));
          return;
        }

        if (isAlreadyScanned) {
          _showErrorSnackBar(
              "This paper has already been scanned. Try another paper.");
          return;
        }

        try {
          preResolvedMetadata = await ApiService.resolveSheet(rawIdentifier);
        } catch (error) {
          if (mounted) _showErrorSnackBar(_sheetCheckError(error));
          return;
        }

        try {
          final exam = preResolvedMetadata['exams'];
          final templateId = exam?['template_id']?.toString();
          final examId = exam?['id']?.toString() ?? '';

          // 1. FIRST: Check actual questions count in exam
          if (examId.isNotEmpty) {
            final questions = await SupabaseService.getExamQuestions(examId);
            if (questions.isNotEmpty) {
              final qCount = questions.length;
              final mCount = questions
                  .where(
                      (q) => (q['question_type'] ?? q['questionType']) == 'MCQ')
                  .length;
              final tCount = questions
                  .where(
                      (q) => (q['question_type'] ?? q['questionType']) == 'TF')
                  .length;

              final matched = AnswerSheetTemplateRegistry.forConfiguration(
                  qCount, mCount, tCount);
              resolvedTemplate = matched;
            }
          }

          // 2. SECOND: If questions were empty, check DB columns total_questions or template_id
          if (resolvedTemplate is Standard50QuestionsTemplate) {
            final totalQs = (exam?['total_questions'] as num?)?.toInt() ?? 0;
            final mcqCount = (exam?['mcq_count'] as num?)?.toInt() ?? 0;
            final tfCount = (exam?['tf_count'] as num?)?.toInt() ?? 0;

            if (totalQs > 0) {
              final matched = AnswerSheetTemplateRegistry.forConfiguration(
                  totalQs, mcqCount, tfCount);
              resolvedTemplate = matched;
            } else if (templateId != null && templateId.isNotEmpty) {
              final matched = AnswerSheetTemplateRegistry.byId(templateId);
              if (matched != null) {
                resolvedTemplate = matched;
              }
            }
          }
        } catch (e) {
          debugPrint("Pre-capture template resolution notice: $e");
        }
      }

      // 2. Spawn a dedicated isolate for heavy OMR processing with the resolved template
      final request = OmrRequest(
        bytes: bytes,
        corners: corners,
        template: resolvedTemplate,
        expectedQr: _lockedSheetQr,
        developerSandbox: _developerSandbox,
        calibrationProfiles: AppBuild.developerTools
            ? await DeveloperTemplateStore.load()
            : const [],
      );

      final processedSheet = await ImageProcessor.processOmr(request);

      if (mounted) {
        if (processedSheet != null) {
          await _handleProcessedSheet(processedSheet,
              preResolvedMetadata: preResolvedMetadata,
              processingTemplate: resolvedTemplate);
        } else {
          _showErrorSnackBar("Could not process sheet. Please try again.");
        }
      }
    } on SheetAlignmentException catch (e) {
      if (mounted) _showErrorSnackBar(e.toString());
    } on SheetIdentityException catch (e) {
      if (mounted) _showErrorSnackBar(e.toString());
    } catch (e) {
      if (mounted) _showErrorSnackBar("Capture failed: $e");
    } finally {
      _resetDetectionForNextSheet();
      await _resumeCameraStream();
    }
  }
}

class EdgePainter extends CustomPainter {
  final List<Offset> corners;
  final bool isDetected;
  final Color color;
  EdgePainter(
      {required this.corners, this.isDetected = false, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final paint = Paint()
      ..color = isDetected ? color.withValues(alpha: 0.8) : Colors.white24
      ..strokeWidth = isDetected ? 3 : 1
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = isDetected ? color.withValues(alpha: 0.1) : Colors.transparent
      ..style = PaintingStyle.fill;

    final pts = corners
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();
    double cx = pts.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    double cy = pts.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    pts.sort((a, b) => math
        .atan2(a.dy - cy, a.dx - cx)
        .compareTo(math.atan2(b.dy - cy, b.dx - cx)));

    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
    if (isDetected) {
      for (final point in pts) {
        canvas.drawRect(
            Rect.fromCenter(center: point, width: 24, height: 24), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
