import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/image_processor.dart';
import '../models/omr/templates/py_image_search_5.dart';
import '../models/omr/processed_sheet.dart';
import 'ai_analysis_screen.dart';

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
  bool _isFocusLocked = false;
  int _detectionCounter = 0;
  static const int _detectionPersistenceThreshold = 3; // Frames to persist detection
  
  // Production parameters (tuned for optimal detection)
  final double _cannyThresh1 = 60.0;
  final double _cannyThresh2 = 180.0;
  final double _blurSigma = 1.2;
  final double _sensitivity = 0.02;
  final int _rotationIndex = 1; // 90° CW is standard for most Android
  
  List<Offset>? _detectedCorners;
  List<double>? _rawCorners; // Store raw normalized corners for OMR request
  Offset? _focusPoint;
  DateTime _lastUIUpdate = DateTime.now();

  // Isolate variables for background CV processing
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _lockOrientationAndStart();
    }
  }

  Future<void> _lockOrientationAndStart() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _startIsolate();
    _initializeCamera();
  }

  @override
  void didUpdateWidget(ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _lockOrientationAndStart();
      } else {
        _disposeCameraAndRestore();
      }
    }
  }

  void _disposeCameraAndRestore() async {
    // Explicitly turn off flash if on
    if (_isFlashOn && _controller != null) {
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint("Failed to turn off flash during disposal: $e");
      }
    }
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller?.stopImageStream();
    _controller?.dispose();
    _controller = null;
    _isolate?.kill();
    _isolate = null;
    _isInitialized = false;
    _paperDetected = false;
    _detectedCorners = null;
    _isFlashOn = false;
  }

  Future<void> _startIsolate() async {
    _isolate = await Isolate.spawn(ImageProcessor.edgeDetectionWorker, _mainReceivePort.sendPort);
    
    if (!_isListening) {
      _isListening = true;
      _mainReceivePort.listen((message) {
        if (message is SendPort) {
          _isolateSendPort = message;
        } else if (message is ScanResponse) {
          if (mounted) {
            // Live scanning frames
            if (!_isProcessing) {
              // Only update if we aren't busy with a high-res capture
              _handleLiveResponse(message);
            }
          }
        } else if (message is ProcessedSheet) {
          _onOmrComplete(message);
        } else {
          // Handle error cases (null or false)
          if (mounted && _isProcessing) {
            setState(() => _isProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Processing failed. Please try again.')),
            );
          }
        }
      });
    }
  }

  void _handleLiveResponse(ScanResponse message) {
    // Implementation of Detection Hysteresis/Persistence
    if (message.foundPaper) {
      _detectionCounter = _detectionPersistenceThreshold;
      _rawCorners = message.corners;
    } else if (_detectionCounter > 0) {
      _detectionCounter--;
    }

    final bool currentlyDetected = _detectionCounter > 0;

    // Trigger focus lock when we first achieve stable detection
    if (currentlyDetected && !_paperDetected && !_isFocusLocked) {
      _lockFocus();
    } else if (!currentlyDetected && _paperDetected) {
      _unlockFocus();
    }

    // Throttle UI updates to keep camera smooth and responsive
    if (DateTime.now().difference(_lastUIUpdate).inMilliseconds > 70) {
      setState(() {
        _paperDetected = currentlyDetected;
        if (message.corners != null) {
          _detectedCorners = [];
          for (var i = 0; i < message.corners!.length; i += 2) {
            _detectedCorners!.add(Offset(message.corners![i], message.corners![i+1]));
          }
        } else if (!_paperDetected) {
          _detectedCorners = null;
        }
      });
      _lastUIUpdate = DateTime.now();
    }
  }

  void _onOmrComplete(ProcessedSheet sheet) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIAnalysisScreen(processedSheet: sheet),
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high, // 720p for smooth high-quality preview
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      
      // Stabilization: Set initial focus and exposure modes
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint("Focus/Exposure stabilization not supported: $e");
      }
      
      _controller!.startImageStream((CameraImage image) {
        if (_isProcessing || _isolateSendPort == null) return;

        // Skip frames while processing high-res or if busy
        _isolateSendPort!.send(ScanRequest(
          bytes: image.planes[0].bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: image.planes[0].bytesPerRow,
          replyPort: _mainReceivePort.sendPort,
          cannyThreshold1: _cannyThresh1,
          cannyThreshold2: _cannyThresh2,
          blurSigma: _blurSigma,
          sensitivity: _sensitivity,
          rotationIndex: _rotationIndex,
          returnDebugImage: false,
        ));
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  @override
  void dispose() {
    _disposeCameraAndRestore();
    _mainReceivePort.close();
    super.dispose();
  }

  Future<void> _lockFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusMode(FocusMode.locked);
      setState(() => _isFocusLocked = true);
      debugPrint("SCANNER: Focus LOCKED for capture");
    } catch (e) {
      debugPrint("Focus lock failed: $e");
    }
  }

  Future<void> _unlockFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusMode(FocusMode.auto);
      setState(() => _isFocusLocked = false);
      debugPrint("SCANNER: Focus UNLOCKED (hunting)");
    } catch (e) {
      debugPrint("Focus unlock failed: $e");
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      debugPrint("Flash toggle failed: $e");
    }
  }

  Future<void> _handleTapToFocus(TapDownDetails details, BuildContext context) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final offset = details.localPosition;
      final RenderBox box = context.findRenderObject() as RenderBox;
      final Size boxSize = box.size;
      
      final double nx = offset.dy / boxSize.height;
      final double ny = 1.0 - (offset.dx / boxSize.width);
      
      setState(() {
        _focusPoint = offset;
      });

      await _controller!.setFocusMode(FocusMode.locked);
      await _controller!.setFocusPoint(Offset(nx, ny));
      await _controller!.setExposurePoint(Offset(nx, ny));
      await _controller!.setFocusMode(FocusMode.auto);
      
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _focusPoint = null;
        });
      }
    } catch (e) {
      debugPrint("Tap to focus failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview with AspectRatio and Tap-to-Focus
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _handleTapToFocus(details, context),
                    child: CameraPreview(_controller!),
                  ),
                  
                  if (_detectedCorners != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: EdgePainter(
                            corners: _detectedCorners!,
                            isDetected: _paperDetected,
                          ),
                        ),
                      ),
                    ),
                  
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 40,
                      top: _focusPoint!.dy - 40,
                      child: IgnorePointer(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellowAccent, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Guide frame
          Positioned(
            top: MediaQuery.of(context).size.height * 0.12,
            left: 0, right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.height * 0.55,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _paperDetected ? Colors.yellowAccent : Colors.blueAccent.withAlpha(100), 
                      width: 1
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _paperDetected ? null : const Center(
                    child: Text(
                      'Align Answer Sheet',
                      style: TextStyle(color: Colors.blueAccent, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Header UI
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 28),
                    onPressed: _toggleFlash,
                  ),
                  Expanded(
                    child: Center(
                      child: _paperDetected 
                        ? const Chip(
                            backgroundColor: Colors.yellowAccent,
                            label: Text('READY TO SCAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          )
                        : const Text(
                            'Detecting edges...',
                            style: TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                    ),
                  ),
                  const SizedBox(width: 48), 
                ],
              ),
            ),
          ),
          
          // Capture Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                heroTag: null,
                onPressed: () async {
                  if (_isProcessing || _controller == null || _rawCorners == null) return;

                  // 1. Stabilization and Capture
                  if (_isFlashOn) await _toggleFlash();
                  
                  setState(() => _isProcessing = true);
                  debugPrint("SCANNER: Starting high-res capture...");
                  
                  try {
                    // 1. Capture High-Res Image
                    final XFile photo = await _controller!.takePicture();
                    final Uint8List bytes = await photo.readAsBytes();
                    debugPrint("SCANNER: Capture complete, bytes: ${bytes.length}");

                    // 2. Request High-Res OMR Processing
                    if (_rawCorners != null) {
                      _isolateSendPort?.send(OmrRequest(
                        bytes: bytes,
                        corners: _rawCorners!,
                        template: PyImageSearch5Template(),
                        replyPort: _mainReceivePort.sendPort,
                      ));
                    } else {
                      debugPrint("SCANNER ERROR: rawCorners null at capture time");
                      setState(() => _isProcessing = false);
                    }
                  } catch (e) {
                    debugPrint("SCANNER ERROR during capture: $e");
                    setState(() => _isProcessing = false);
                  }
                },
                backgroundColor: _paperDetected ? Colors.yellowAccent : Colors.blueAccent,
                child: _isProcessing 
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Icon(Icons.camera_alt, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EdgePainter extends CustomPainter {
  final List<Offset> corners;
  final bool isDetected;

  EdgePainter({
    required this.corners, 
    this.isDetected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    final paint = Paint()
      ..color = isDetected ? Colors.yellowAccent : Colors.blueAccent
      ..strokeWidth = isDetected ? 5 : 2
      ..style = PaintingStyle.stroke;

    List<Offset> transformed = corners.map((p) {
      return Offset(p.dx * size.width, p.dy * size.height);
    }).toList();

    List<Offset> sorted = _sortCorners(transformed);

    final path = Path()
      ..moveTo(sorted[0].dx, sorted[0].dy)
      ..lineTo(sorted[1].dx, sorted[1].dy)
      ..lineTo(sorted[2].dx, sorted[2].dy)
      ..lineTo(sorted[3].dx, sorted[3].dy)
      ..close();

    canvas.drawPath(path, paint);
    
    for (var p in sorted) {
      canvas.drawCircle(p, 6, Paint()..color = paint.color);
    }
  }

  List<Offset> _sortCorners(List<Offset> pts) {
    if (pts.length != 4) return pts;

    double centerX = 0, centerY = 0;
    for (var p in pts) {
      centerX += p.dx;
      centerY += p.dy;
    }
    centerX /= 4;
    centerY /= 4;

    List<Offset> sorted = List.from(pts);
    sorted.sort((a, b) {
      return (math.atan2(a.dy - centerY, a.dx - centerX))
          .compareTo(math.atan2(b.dy - centerY, b.dx - centerX));
    });

    return sorted;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
