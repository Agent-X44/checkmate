import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../services/image_processor.dart';
import '../services/api_service.dart';
import '../services/cv/qr_classification_service.dart';
import '../services/supabase_service.dart';
import '../services/deep_link_service.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/qr_data.dart';
import '../models/omr/templates/standard_50_questions.dart';
import '../utils/ui_utils.dart';
import 'ai_analysis_screen.dart';

/// Screen responsible for live camera feed and document edge detection.
/// Enforces:
/// - BR-06: Local Edge OMR Processing (Isolate-based).
/// - BR-04: Student ID recognition.
class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final bool isActive;
  final VoidCallback? onClose;
  const ScannerScreen({
    super.key,
    required this.cameras,
    required this.isActive,
    this.onClose,
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
  int _detectionCounter = 0;
  static const int _detectionPersistenceThreshold = 2;

  // Course Invitation Confirmation Card State
  bool _isConfirmationCardOpen = false;
  String? _lastScannedInviteCode;
  DateTime? _lastInvitePromptTime;

  // Pipeline control flags
  //  - _qrFirstMode: Initial short window where QR detection is prioritized (invitation QR must be handled first)
  //  - _edgesDetectedOnce: Becomes true once paper edges were confidently detected; only then allow answer-sheet QR handling
  bool _qrFirstMode = true;
  bool _edgesDetectedOnce = false;

  bool get _isProcessing => _isOmrProcessing || _isConfirmationCardOpen;

  bool get _canCapturePaper =>
      !_isProcessing &&
      _controller != null &&
      _controller!.value.isInitialized &&
      _paperDetected &&
      _rawCorners != null &&
      _rawCorners!.length >= 8;

  // Isolate state
  bool _isIsolateWorking = false;

  List<Offset>? _detectedCorners;
  List<double>? _rawCorners;
  List<Offset>? _detectedQrCorners;
  QrData? _detectedLiveQr;
  String _lastQrDebugText = 'QR: waiting';
  Offset? _focusPoint;
  DateTime _lastUIUpdate = DateTime.now();

  // Session Management (BR-07: Results retained on device until Finish)
  final List<ProcessedSheet> _scannedResults = [];
  final Set<String> _processedSheetIds = {};

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  DateTime? _lastQrScanTime;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startCapture();
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
        _disposeCameraAndRestore();
      }
    }
  }

  Future<void> _disposeCameraOnly() async {
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
  }

  /// Offloads heavy CV processing to a separate Isolate to prevent UI jank.
  Future<void> _startIsolate() async {
    if (_isolate != null) return;
    _isolate = await Isolate.spawn(
        ImageProcessor.edgeDetectionWorker, _mainReceivePort.sendPort);
    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is ScanResponse && mounted && !_isProcessing) {
        _handleLiveResponse(message);
      } else if (message is ProcessedSheet && mounted) {
        _handleProcessedSheet(message);
      }
    });
  }

  void _handleLiveResponse(ScanResponse message) {
    _isIsolateWorking = false;

    // 1. Detect whether the current frame contains a Course Invitation QR
    final inviteCode = message.detectedQr == null
        ? null
        : QrClassificationService.extractInvitationCodeFromQr(message.detectedQr!);

    final isCourseInvite = inviteCode != null;

    if (isCourseInvite) {
      // SUPPRESS PAPER DETECTION: This is a Course Invitation QR, NOT an OMR Answer Sheet!
      _detectionCounter = 0;
      _rawCorners = null;
      _lastQrDebugText = 'QR: course invite ${inviteCode}';

      // Render Google Lens-style yellow bounding box overlay around the Course QR code
      if (message.qrCorners != null && message.qrCorners!.length >= 8) {
        _detectedQrCorners = List.generate(
          4,
          (i) => Offset(message.qrCorners![i * 2], message.qrCorners![i * 2 + 1]),
        );
        _detectedLiveQr = message.detectedQr;
      } else {
        _detectedQrCorners = null;
        _detectedLiveQr = null;
      }

      // Update UI to ensure "PAPER DETECTED" is strictly hidden while scanning Course QR
      if (DateTime.now().difference(_lastUIUpdate).inMilliseconds > 100) {
        if (mounted) {
          setState(() {
            _paperDetected = false;
            _detectedCorners = null;
          });
          _lastUIUpdate = DateTime.now();
        }
      }

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
    if (candidateQr != null && candidateQr.sheetIdentifier.isNotEmpty && candidateQr.sheetIdentifier != 'UNKNOWN') {
      final inviteCode = QrClassificationService.extractInvitationCodeFromQr(candidateQr);
      if (inviteCode == null) {
        final coords = message.qrCorners != null && message.qrCorners!.length >= 8
            ? message.qrCorners!
            : const [0.20, 0.20, 0.80, 0.20, 0.80, 0.80, 0.20, 0.80];
        _detectedQrCorners = List.generate(4, (i) => Offset(coords[i * 2], coords[i * 2 + 1]));
        _detectedLiveQr = candidateQr;
        _lastQrDebugText = 'QR: ${candidateQr.sheetIdentifier}';
      } else {
        _detectedQrCorners = null;
        _detectedLiveQr = null;
        _lastQrDebugText = 'QR: invite candidate ${inviteCode}';
      }
    } else {
      _detectedQrCorners = null;
      _detectedLiveQr = null;
      _lastQrDebugText = 'QR: waiting';
    }

    // 2. Paper edge detection for OMR answer sheets
    if (message.foundPaper && !_qrFirstMode) {
      _detectionCounter = _detectionPersistenceThreshold;
      _rawCorners = message.corners;
    } else if (_detectionCounter > 0) {
      _detectionCounter--;
    }

    final detected = _detectionCounter > 0;
    // Throttled UI updates (10fps max for detection overlays)
    if (DateTime.now().difference(_lastUIUpdate).inMilliseconds > 100) {
      if (mounted) {
        setState(() {
          _paperDetected = detected;
          if (detected) _edgesDetectedOnce = true;

          if (message.corners != null) {
            _detectedCorners = List.generate(
                message.corners!.length ~/ 2,
                (i) => Offset(
                    message.corners![i * 2], message.corners![i * 2 + 1]));
          } else if (!_paperDetected) {
            _detectedCorners = null;
          }
        });
        _lastUIUpdate = DateTime.now();
      }
    }
  }

  String _normalizeJoinCode(String raw) {
    return raw
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .trim()
        .toUpperCase();
  }

  Future<bool> _validateCourseCodeBeforeJoin(String inviteCode) async {
    final normalizedCode = _normalizeJoinCode(inviteCode);
    debugPrint('QR JOIN DEBUG: validating code raw="$inviteCode" normalized="$normalizedCode"');

    try {
      final courseData = await SupabaseService.getCourseDataByCode(normalizedCode).timeout(
        const Duration(seconds: 3),
      );
      debugPrint('QR JOIN DEBUG: validation result for $normalizedCode => ${courseData != null ? courseData['id'] : 'NOT_FOUND'}');
      return courseData != null;
    } catch (e) {
      debugPrint('QR JOIN DEBUG: validation exception for $normalizedCode :: $e');
      return false;
    }
  }

  Future<void> _joinCourseFromPrompt(String inviteCode, BuildContext bottomSheetContext) async {
    final normalizedCode = _normalizeJoinCode(inviteCode);
    debugPrint('JOIN COURSE BUTTON: pressed raw="$inviteCode" normalized="$normalizedCode"');

    final isValidCourse = await _validateCourseCodeBeforeJoin(normalizedCode);
    if (!isValidCourse) {
      final fallbackContext = navigatorKey.currentContext ?? context;
      if (fallbackContext.mounted) {
        CheckMateUi.showTopPrompt(
          fallbackContext,
          'Course code $normalizedCode is not available or lookup failed.',
          isError: true,
        );
      }
      return;
    }

    try {
      debugPrint('JOIN COURSE: starting direct Supabase join for $normalizedCode');

      final targetContext = navigatorKey.currentContext ?? context;
      if (targetContext.mounted) {
        CheckMateUi.showTopPrompt(targetContext, 'Joining course ($normalizedCode)...', isError: false);
      }

      final course = await SupabaseService.joinClass(normalizedCode).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception('Course join timed out. Please check your network and try again.'),
      );

      if (mounted) {
        _isConfirmationCardOpen = false;
      }

      if (Navigator.of(bottomSheetContext, rootNavigator: true).canPop()) {
        Navigator.of(bottomSheetContext, rootNavigator: true).pop();
      }

      debugPrint('JOIN COURSE: success for $normalizedCode -> ${course.name}');
      if (targetContext.mounted) {
        CheckMateUi.showTopPrompt(
          targetContext,
          'Successfully joined course: ${course.name}!',
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('JOIN COURSE: failed for $normalizedCode :: $e');
      final fallbackContext = navigatorKey.currentContext ?? context;
      if (fallbackContext.mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        CheckMateUi.showTopPrompt(fallbackContext, msg, isError: true);
      }
    }
  }

  Future<void> _triggerCourseJoinPrompt(String inviteCode) async {
    if (_isConfirmationCardOpen || !mounted) return;

    // Debounce duplicate scans of same code within 3 seconds
    if (_lastScannedInviteCode == inviteCode &&
        _lastInvitePromptTime != null &&
        DateTime.now().difference(_lastInvitePromptTime!).inMilliseconds < 1000) {
      return;
    }

    // Synchronously lock state immediately to prevent live camera stream race conditions
    _isConfirmationCardOpen = true;
    _lastScannedInviteCode = inviteCode;
    _lastInvitePromptTime = DateTime.now();

    // 1. Verify if this QR code is a valid course in database & check creator status
    final normalizedInviteCode = _normalizeJoinCode(inviteCode);
    Map<String, dynamic>? courseData;
    try {
      courseData = await SupabaseService.getCourseDataByCode(normalizedInviteCode).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint("Course lookup error: $e");
    }

    if (!mounted) return;

    // If this code is not yet found in the database, still surface the join prompt when it
    // looks like an invitation code so the user can take action immediately.
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;

    if (courseData == null) {
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
                  'Course Code: $normalizedInviteCode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Would you like to join this course?',
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
                          if (Navigator.of(bottomSheetContext, rootNavigator: true).canPop()) {
                            Navigator.of(bottomSheetContext, rootNavigator: true).pop();
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
                          await _joinCourseFromPrompt(normalizedInviteCode, bottomSheetContext);
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
      return;
    }

    // 2. Check if current user is the course creator
    final currentUser = SupabaseService.currentUser;
    final instructorId = courseData['instructor_id']?.toString().trim();
    final currentUserId = currentUser?.id.trim();

    if (instructorId != null && currentUserId != null && instructorId == currentUserId) {
      await _showCreatorNoticeCard(inviteCode, courseData['name'] ?? '');
      if (mounted) {
        _isConfirmationCardOpen = false;
      }
      return;
    }

    // 3. Valid course & user is student: Open Course Join Confirmation Card

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
                'Course Code: $inviteCode',
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
                        if (Navigator.of(bottomSheetContext, rootNavigator: true).canPop()) {
                          Navigator.of(bottomSheetContext, rootNavigator: true).pop();
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
                        await _joinCourseFromPrompt(inviteCode, bottomSheetContext);
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

  Future<void> _showCreatorNoticeCard(String inviteCode, String courseName) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
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
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Course Creator Notice',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              if (courseName.isNotEmpty)
                Text(
                  courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber,
                  ),
                ),
              Text(
                'Code: $inviteCode',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "You can't join the course you've created.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (Navigator.of(bottomSheetContext, rootNavigator: true).canPop()) {
                      Navigator.of(bottomSheetContext, rootNavigator: true).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'UNDERSTOOD',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  String? _extractInviteCode(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;

    // 1. URL with ?code= or ?joinCode=
    if (clean.contains('code=')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
        if (codeParam != null && codeParam.trim().isNotEmpty) {
          return codeParam.trim().toUpperCase();
        }
      }
    }

    // 2. Extract from URL (Any domain, looking for code param or short alphanumeric path segment)
    final uri = Uri.tryParse(clean);
    if (uri != null && uri.scheme.isNotEmpty) {
      final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
      if (codeParam != null && codeParam.trim().isNotEmpty) {
        return codeParam.trim().toUpperCase();
      }
      if (uri.pathSegments.isNotEmpty) {
        // Check if any of the last path segments is a valid 5-8 char code (e.g. /course/EDJNRU)
        final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
        if (segments.isNotEmpty) {
          final lastSegment = segments.last.trim().toUpperCase();
          if (RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(lastSegment) && 
              !lastSegment.startsWith("SHEET") && 
              !lastSegment.contains("UNKNOWN")) {
            return lastSegment;
          }
        }
      }
    }

    // 3. Format: "Code: EDJNRU" or "Code EDJNRU" or "JOIN: EDJNRU"
    if (clean.toUpperCase().contains("CODE") || clean.toUpperCase().contains("JOIN")) {
      final match = RegExp(r'[A-Z0-9]{5,8}').firstMatch(
        clean.toUpperCase().replaceAll("CODE", "").replaceAll("JOIN", "").replaceAll(":", "").trim(),
      );
      if (match != null) {
        return match.group(0);
      }
    }

    // 4. Raw Join Code: 5 to 8 uppercase alphanumeric characters (e.g. EDJNRU)
    final isAlphanumericCode = RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(clean.toUpperCase());
    if (isAlphanumericCode && 
        !clean.toLowerCase().startsWith("sheet") && 
        !clean.contains("-AUTO") && 
        !clean.toLowerCase().contains("unknown") &&
        !clean.toLowerCase().contains("cm50") &&
        !clean.toLowerCase().contains("py5")) {
      return clean.toUpperCase();
    }

    return null;
  }

  /// BR-05 Enforcement: Resolve Sheet ID via backend before grading.
  Future<void> _handleProcessedSheet(ProcessedSheet sheet) async {
    try {
      final qrData = sheet.qrData;
      final rawIdentifier = qrData?.sheetIdentifier ?? '';

      // 1. FIRST: Detect whether this QR is actually a Course Invitation.
      final inviteCode = qrData == null ? null : QrClassificationService.extractInvitationCodeFromQr(qrData);
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

      // 3. Prevent duplicates in same session
      if (_processedSheetIds.contains(rawIdentifier)) {
        _showErrorSnackBar("Duplicate: This sheet was already scanned.");
        return;
      }

      // 4. Resolve metadata from Supabase
      // This verifies if the sheet actually belongs to this exam/student
      final metadata = await ApiService.resolveSheet(rawIdentifier);
      
      if (mounted) {
        _scannedResults.add(sheet);
        _processedSheetIds.add(rawIdentifier);
        _showSuccessSnackBar("Verified: ${metadata['student_name']}");
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = "Invalid paper, please try again.";
        if (e.toString().contains("404")) {
          errorMsg = "Invalid paper: Sheet ID not found. Please try again.";
        } else if (e.toString().contains("403")) {
          errorMsg = "Unauthorized: Assessment is not approved yet.";
        }
        
        _showErrorSnackBar(errorMsg);
      }
    } finally {
      if (mounted) {
        setState(() => _isOmrProcessing = false);
      }
    }
  }

  void _showErrorSnackBar(String msg) {
    CheckMateUi.showTopPrompt(context, msg);
  }

  void _showSuccessSnackBar(String msg) {
    CheckMateUi.showTopPrompt(context, msg, isError: false);
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
      cams[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      _controller!.startImageStream((image) {
        if (_isProcessing || _isolateSendPort == null || _isIsolateWorking) return;

        unawaited(_tryDecodeQrFromCameraFrame(image));
        
        _isIsolateWorking = true;
        _isolateSendPort!.send(ScanRequest(
          bytes: image.planes[0].bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: image.planes[0].bytesPerRow,
          replyPort: _mainReceivePort.sendPort,
        ));
      });
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isFlashOn = false;
          // Start in QR-first mode to prioritize course invitation detection
          _qrFirstMode = true;
          _edgesDetectedOnce = false;
        });

        // After a short QR-first window, enable edge detection. If a course invite QR appears in
        // that window it will be handled immediately; otherwise the camera will begin looking for edges.
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          setState(() {
            _qrFirstMode = false;
          });
        });
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  Future<void> _handleTapToFocus(TapDownDetails details, Size widgetSize) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final offset = details.localPosition;
      final nx = offset.dy / widgetSize.height;
      final ny = 1.0 - (offset.dx / widgetSize.width);
      setState(() => _focusPoint = offset);
      await _controller!.setFocusPoint(Offset(nx.clamp(0.05, 0.95), ny.clamp(0.05, 0.95)));
      await _controller!.setExposurePoint(Offset(nx.clamp(0.05, 0.95), ny.clamp(0.05, 0.95)));
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _focusPoint = null);
    } catch (_) {}
  }

  Future<void> _tryDecodeQrFromCameraFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_lastQrScanTime != null && now.difference(_lastQrScanTime!).inMilliseconds < 300) return;
    _lastQrScanTime = now;

    try {
      final isAndroid = Platform.isAndroid;
      final inputFormat = isAndroid ? InputImageFormat.nv21 : InputImageFormat.yuv420;
      final bytes = isAndroid ? image.planes[0].bytes : _concatenatePlanes(image);
      final bytesPerRow = image.planes.first.bytesPerRow;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: inputFormat,
          bytesPerRow: bytesPerRow,
        ),
      );

      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!mounted || barcodes.isEmpty) return;

      final rawValue = barcodes.first.rawValue ?? '';
      if (rawValue.trim().isEmpty) return;

      final candidate = QrData.fromRaw(rawValue);
      if (candidate.sheetIdentifier.isEmpty || candidate.sheetIdentifier == 'UNKNOWN') return;

      final inviteCode = QrClassificationService.extractInvitationCodeFromQr(candidate);
      final normalizedCorners = barcodes.first.cornerPoints.isNotEmpty
          ? List.generate(4, (index) {
              final point = barcodes.first.cornerPoints[index];
              final x = (point.x.toDouble() / image.width).clamp(0.0, 1.0);
              final y = (point.y.toDouble() / image.height).clamp(0.0, 1.0);
              return Offset(x, y);
            })
          : const [
              Offset(0.20, 0.20),
              Offset(0.80, 0.20),
              Offset(0.80, 0.80),
              Offset(0.20, 0.80),
            ];

      if (inviteCode != null) {
        _lastQrDebugText = 'QR: invite candidate $inviteCode';
        if (mounted) {
          setState(() {
            _detectedLiveQr = candidate;
            _detectedQrCorners = normalizedCorners;
          });
          await _triggerCourseJoinPrompt(inviteCode);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _detectedLiveQr = candidate;
          _lastQrDebugText = 'QR: ${candidate.sheetIdentifier}';
          _detectedQrCorners = normalizedCorners;
        });
      }
    } catch (e) {
      debugPrint('QR decode failed: $e');
    }
  }

  Uint8List _concatenatePlanes(CameraImage image) {
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  @override
  void deactivate() {
    super.deactivate();
    _disposeCameraAndRestore();
  }

  @override
  void dispose() {
    _disposeCameraAndRestore();
    _mainReceivePort.close();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)));
    }
    final size = MediaQuery.of(context).size;
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
                                  border: Border.all(color: accentColor, width: 1.5)))),
                    if (_detectedCorners != null)
                      Positioned.fill(
                          child: IgnorePointer(
                              child: CustomPaint(
                                  painter: EdgePainter(
                                      corners: _detectedCorners!,
                                      isDetected: _paperDetected,
                                      color: accentColor)))),
                    if (_detectedQrCorners != null && _detectedLiveQr != null)
                      Positioned.fill(
                          child: IgnorePointer(
                              child: CustomPaint(
                                  painter: QrBoundingBoxPainter(
                                      corners: _detectedQrCorners!,
                                      label: _extractInviteCode(_detectedLiveQr!.sheetIdentifier) != null
                                          ? "Course Code: ${_extractInviteCode(_detectedLiveQr!.sheetIdentifier)}"
                                          : "Answer Sheet QR",
                                      color: _extractInviteCode(_detectedLiveQr!.sheetIdentifier) != null
                                          ? (isDark ? Colors.yellowAccent : Colors.amber)
                                          : Colors.greenAccent)))),
                  ]);
                }),
              ),
            ),
          ),
          
          if (_isOmrProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: accentColor),
                    const SizedBox(height: 16),
                    const Text("IDENTIFYING STUDENT...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ],
                ),
              ),
            ),

          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                  child: Text("SCANNED: ${_scannedResults.length}", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Container(
                  constraints: const BoxConstraints(maxWidth: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    _lastQrDebugText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
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
            top: 100,
            left: 20,
            child: FloatingActionButton.small(
              heroTag: 'flash',
              onPressed: () async {
                final nextMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
                await _controller?.setFlashMode(nextMode);
                setState(() => _isFlashOn = !_isFlashOn);
              },
              backgroundColor: Colors.black45,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_paperDetected && !_isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                      decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(30)),
                      child: const Text("PAPER DETECTED", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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
                        backgroundColor: _canCapturePaper ? accentColor : Colors.white24,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                        child: const Icon(Icons.qr_code_scanner, color: Colors.black, size: 40),
                      ),
                    ),
                  ],
                ),
                if (_scannedResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: TextButton(
                      onPressed: _finishSession,
                      child: Text("FINISH SESSION (${_scannedResults.length})", 
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Future<void> _captureAndProcess() async {
  if (!_canCapturePaper) {
    final inviteCode = _detectedLiveQr == null
        ? null
        : QrClassificationService.extractInvitationCodeFromQr(_detectedLiveQr!);
    if (inviteCode != null) {
      _isConfirmationCardOpen = false;
      await _triggerCourseJoinPrompt(inviteCode);
      return;
    }
    _showErrorSnackBar('Align the answer sheet and wait until paper detection is active.');
    return;
  }

  final corners = _rawCorners != null ? List<double>.from(_rawCorners!) : <double>[];
  setState(() => _isOmrProcessing = true);

    try {
      final XFile photo = await _controller!.takePicture();
      final Uint8List bytes = await photo.readAsBytes();

      // [LABEL: Architecture - Isolation & Parallelism]
      // Spawn a dedicated, short-lived isolate for the heavy OMR processing.
      // This prevents the live camera feed (edgeDetectionWorker) from dropping frames 
      // or blocking the UI thread while the user waits for the processing.
      final request = OmrRequest(
        bytes: bytes,
        corners: corners,
        template: Standard50QuestionsTemplate(),
        expectedQr: _detectedLiveQr,
      );
      
      final processedSheet = await ImageProcessor.processOmr(request);

      if (mounted) {
        if (processedSheet != null) {
          await _handleProcessedSheet(processedSheet);
        } else {
          _showErrorSnackBar("Could not process sheet. Please try again.");
          setState(() => _isOmrProcessing = false);
        }
      }
    } catch (e) {
      _showErrorSnackBar("Capture failed: $e");
      if (mounted) setState(() => _isOmrProcessing = false);
    }
  }

  void _finishSession() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AIAnalysisScreen(
          sheets: _scannedResults,
        ),
      ),
    );
  }
}

class QrBoundingBoxPainter extends CustomPainter {
  final List<Offset> corners;
  final String label;
  final Color color;

  QrBoundingBoxPainter({
    required this.corners,
    required this.label,
    required this.color,
  });

  List<Offset> _sortedCorners() {
    if (corners.length != 4) return corners;

    final centroid = Offset(
      corners.fold<double>(0, (sum, p) => sum + p.dx) / 4,
      corners.fold<double>(0, (sum, p) => sum + p.dy) / 4,
    );

    final ordered = List<Offset>.from(corners);
    ordered.sort((a, b) {
      final angleA = math.atan2(a.dy - centroid.dy, a.dx - centroid.dx);
      final angleB = math.atan2(b.dy - centroid.dy, b.dx - centroid.dx);
      return angleA.compareTo(angleB);
    });
    return ordered;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final ordered = _sortedCorners();
    final mappedCorners = ordered.map((p) {
      final scaledX = p.dx > 1.0 ? p.dx : p.dx * size.width;
      final scaledY = p.dy > 1.0 ? p.dy : p.dy * size.height;
      return Offset(scaledX.clamp(0.0, size.width), scaledY.clamp(0.0, size.height));
    }).toList();

    final path = Path()
      ..moveTo(mappedCorners[0].dx, mappedCorners[0].dy)
      ..lineTo(mappedCorners[1].dx, mappedCorners[1].dy)
      ..lineTo(mappedCorners[2].dx, mappedCorners[2].dy)
      ..lineTo(mappedCorners[3].dx, mappedCorners[3].dy)
      ..close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final bracketPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const double armLength = 18.0;
    for (int i = 0; i < 4; i++) {
      final pCurr = mappedCorners[i];
      final pNext = mappedCorners[(i + 1) % 4];
      final pPrev = mappedCorners[(i + 3) % 4];

      final dirNext = (pNext - pCurr);
      final lenNext = dirNext.distance;
      if (lenNext > 0) {
        final armNext = pCurr + (dirNext / lenNext) * armLength.clamp(0, lenNext / 2);
        canvas.drawLine(pCurr, armNext, bracketPaint);
      }

      final dirPrev = (pPrev - pCurr);
      final lenPrev = dirPrev.distance;
      if (lenPrev > 0) {
        final armPrev = pCurr + (dirPrev / lenPrev) * armLength.clamp(0, lenPrev / 2);
        canvas.drawLine(pCurr, armPrev, bracketPaint);
      }
    }

    if (label.isNotEmpty) {
      final topMid = Offset(
        (mappedCorners[0].dx + mappedCorners[1].dx + mappedCorners[2].dx + mappedCorners[3].dx) / 4,
        math.min(math.min(mappedCorners[0].dy, mappedCorners[1].dy), math.min(mappedCorners[2].dy, mappedCorners[3].dy)) - 18,
      );

      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final bgWidth = textPainter.width + 20;
      final bgHeight = textPainter.height + 10;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(topMid.dx, topMid.dy - bgHeight / 2),
          width: bgWidth,
          height: bgHeight,
        ),
        const Radius.circular(12),
      );

      final chipPaint = Paint()..color = color;
      canvas.drawRRect(bgRect, chipPaint);
      textPainter.paint(
        canvas,
        Offset(topMid.dx - textPainter.width / 2, topMid.dy - bgHeight / 2 + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant QrBoundingBoxPainter oldDelegate) {
    return oldDelegate.corners != corners || oldDelegate.label != label || oldDelegate.color != color;
  }
}

class EdgePainter extends CustomPainter {
  final List<Offset> corners;
  final bool isDetected;
  final Color color;
  EdgePainter({required this.corners, this.isDetected = false, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;
    final paint = Paint()
      ..color = isDetected ? color.withValues(alpha: 0.5) : Colors.white24
      ..strokeWidth = isDetected ? 3 : 1
      ..style = PaintingStyle.stroke;

    final pts = corners.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    double cx = pts.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    double cy = pts.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    pts.sort((a, b) => math.atan2(a.dy - cy, a.dx - cx).compareTo(math.atan2(b.dy - cy, b.dx - cx)));
    
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
