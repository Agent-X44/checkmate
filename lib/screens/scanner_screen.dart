import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/image_processor.dart';
import '../services/api_service.dart';
import '../models/omr/processed_sheet.dart';
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
  const ScannerScreen({super.key, required this.cameras, required this.isActive});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _paperDetected = false;
  bool _isFlashOn = false;
  int _detectionCounter = 0;
  static const int _detectionPersistenceThreshold = 2;

  List<Offset>? _detectedCorners;
  List<double>? _rawCorners;
  Offset? _focusPoint;
  DateTime _lastUIUpdate = DateTime.now();

  // Session Management (BR-07: Results retained on device until Finish)
  final List<ProcessedSheet> _scannedResults = [];
  final Set<String> _processedSheetIds = {};

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();

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
    if (message.foundPaper) {
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

  /// BR-05 Enforcement: Resolve Sheet ID via backend before grading.
  Future<void> _handleProcessedSheet(ProcessedSheet sheet) async {
    final qrData = sheet.qrData;
    
    // 1. Validate QR detection
    if (qrData == null || qrData.sheetIdentifier.isEmpty) {
      _showErrorSnackBar("Invalid Sheet: QR code could not be decoded.");
      setState(() => _isProcessing = false);
      return;
    }

    final identifier = qrData.sheetIdentifier;

    // 2. Prevent duplicates in same session
    if (_processedSheetIds.contains(identifier)) {
      _showErrorSnackBar("Duplicate: This sheet was already scanned.");
      setState(() => _isProcessing = false);
      return;
    }

    try {
      // 3. Resolve metadata from Supabase
      // This verifies if the sheet actually belongs to this exam/student
      final metadata = await ApiService.resolveSheet(identifier);
      
      if (mounted) {
        setState(() {
          _scannedResults.add(sheet);
          _processedSheetIds.add(identifier);
          _isProcessing = false;
        });
        _showSuccessSnackBar("Verified: ${metadata['student_name']}");
      }
    } catch (e) {
      if (mounted) {
        // Detailed error messages based on API response
        String errorMsg = "Verification Failed: $e";
        if (e.toString().contains("404")) {
          errorMsg = "Unknown Sheet: ID '$identifier' not found in database.";
        } else if (e.toString().contains("403")) {
          errorMsg = "Unauthorized: Assessment is not approved yet.";
        }
        
        _showErrorSnackBar(errorMsg);
        setState(() => _isProcessing = false);
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
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      _controller!.startImageStream((image) {
        if (_isProcessing || _isolateSendPort == null) return;
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

  @override
  void dispose() {
    _disposeCameraAndRestore();
    _mainReceivePort.close();
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
                  ]);
                }),
              ),
            ),
          ),
          
          if (_isProcessing)
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
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
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
                        onPressed: (_paperDetected && !_isProcessing) ? _captureAndProcess : null,
                        backgroundColor: _paperDetected ? accentColor : Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                        child: Icon(Icons.qr_code_scanner, color: _paperDetected ? Colors.black : Colors.white24, size: 40),
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
    if (_isolateSendPort == null || _rawCorners == null) return;
    
    final corners = List<double>.from(_rawCorners!);
    setState(() => _isProcessing = true);

    try {
      final XFile photo = await _controller!.takePicture();
      final Uint8List bytes = await photo.readAsBytes();
      
      _isolateSendPort!.send(OmrRequest(
        bytes: bytes,
        corners: corners,
        template: Standard50QuestionsTemplate(),
        replyPort: _mainReceivePort.sendPort,
      ));
    } catch (e) {
      _showErrorSnackBar("Capture failed: $e");
      setState(() => _isProcessing = false);
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
