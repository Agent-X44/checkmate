import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/image_processor.dart';
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
  int _detectionCounter = 0;
  static const int _detectionPersistenceThreshold = 2;
  
  List<Offset>? _detectedCorners;
  List<double>? _rawCorners;
  Offset? _focusPoint;
  DateTime _lastUIUpdate = DateTime.now();

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
      // Force flash off before disposal
      await controller.setFlashMode(FlashMode.off);
      await controller.dispose();
    } catch (_) {}
    if (mounted) setState(() { _isInitialized = false; _paperDetected = false; _isFlashOn = false; });
  }

  Future<void> _disposeCameraAndRestore() async {
    await _disposeCameraOnly();
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    _isolate?.kill(); _isolate = null;
  }

  Future<void> _startIsolate() async {
    if (_isolate != null) {
      return;
    }
    _isolate = await Isolate.spawn(ImageProcessor.edgeDetectionWorker, _mainReceivePort.sendPort);
    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is ScanResponse && mounted && !_isProcessing) {
        _handleLiveResponse(message);
      }
    });
  }

  void _handleLiveResponse(ScanResponse message) {
    if (message.foundPaper) { _detectionCounter = _detectionPersistenceThreshold; _rawCorners = message.corners; }
    else if (_detectionCounter > 0) { _detectionCounter--; }
    
    final detected = _detectionCounter > 0;
    // Fast processing doesn't need heavy UI updates
    if (DateTime.now().difference(_lastUIUpdate).inMilliseconds > 100) {
      if (mounted) {
        setState(() {
          _paperDetected = detected;
          if (message.corners != null) {
            _detectedCorners = List.generate(message.corners!.length ~/ 2, (i) => Offset(message.corners![i*2], message.corners![i*2+1]));
          } else if (!_paperDetected) {
            _detectedCorners = null;
          }
        });
        _lastUIUpdate = DateTime.now();
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    
    _controller = CameraController(
      widget.cameras[0], 
      ResolutionPreset.high, // HD Live Feed
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      _controller!.startImageStream((image) {
        if (_isProcessing || _isolateSendPort == null) return;
        _isolateSendPort!.send(ScanRequest(
          bytes: image.planes[0].bytes,
          width: image.width, height: image.height,
          bytesPerRow: image.planes[0].bytesPerRow,
          replyPort: _mainReceivePort.sendPort,
        ));
      });
      if (mounted) setState(() { _isInitialized = true; _isFlashOn = false; });
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  @override
  void dispose() { _disposeCameraAndRestore(); _mainReceivePort.close(); super.dispose(); }

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
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.yellowAccent)));
    }
    final size = MediaQuery.of(context).size;
    final cameraValue = _controller!.value;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width, height: size.width * cameraValue.aspectRatio,
              child: AspectRatio(
                aspectRatio: 1 / cameraValue.aspectRatio,
                child: LayoutBuilder(builder: (context, constraints) {
                  final widgetSize = constraints.biggest;
                  return Stack(children: [
                    GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (d) => _handleTapToFocus(d, widgetSize), child: CameraPreview(_controller!)),
                    if (_focusPoint != null) Positioned(left: _focusPoint!.dx - 30, top: _focusPoint!.dy - 30, child: Container(width: 60, height: 60, decoration: BoxDecoration(border: Border.all(color: Colors.yellowAccent, width: 1.5)))),
                    if (_detectedCorners != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: EdgePainter(corners: _detectedCorners!, isDetected: _paperDetected)))),
                  ]);
                }),
              ),
            ),
          ),
          
          if (_paperDetected)
            Positioned(
              top: size.height * 0.45,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.yellowAccent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text('READY TO SCAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.5)),
                ),
              ),
            ),

          Positioned(
            top: 40, left: 20, right: 20,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 28), 
                  onPressed: () async {
                    if (_controller == null) return;
                    final nextMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
                    await _controller!.setFlashMode(nextMode);
                    setState(() => _isFlashOn = !_isFlashOn);
                  }
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: FloatingActionButton.large(
                // Logic: Only enable button if paper is detected
                onPressed: _paperDetected ? () async {
                  if (_isProcessing || _controller == null || _rawCorners == null) return;
                  final corners = List<double>.from(_rawCorners!);
                  setState(() => _isProcessing = true);
                  
                  try {
                    final XFile photo = await _controller!.takePicture();
                    final Uint8List bytes = await photo.readAsBytes();
                    if (mounted) {
                      await _disposeCameraOnly();
                      if (!mounted) return;
                      Navigator.push(context, MaterialPageRoute(builder: (context) => AIAnalysisScreen(rawImage: bytes, rawCorners: corners))).then((_) {
                        if (mounted) {
                          setState(() { _isProcessing = false; _paperDetected = false; _detectedCorners = null; _isFlashOn = false; });
                          _initializeCamera();
                        }
                      });
                    }
                  } catch (e) { 
                    debugPrint("Capture error: $e");
                    if (mounted) { setState(() { _isProcessing = false; _isFlashOn = false; }); _initializeCamera(); } 
                  }
                } : null,
                backgroundColor: _paperDetected ? Colors.yellowAccent : Colors.white10,
                child: Icon(Icons.camera, color: _paperDetected ? Colors.black : Colors.white24, size: 36),
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
  EdgePainter({required this.corners, this.isDetected = false});
  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = isDetected ? Colors.yellowAccent.withValues(alpha: 0.5) : Colors.white24
      ..strokeWidth = isDetected ? 3 : 1
      ..style = PaintingStyle.stroke;
      
    final pts = corners.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    double cx = pts.map((p)=>p.dx).reduce((a,b)=>a+b)/4;
    double cy = pts.map((p)=>p.dy).reduce((a,b)=>a+b)/4;
    pts.sort((a,b) => math.atan2(a.dy-cy, a.dx-cx).compareTo(math.atan2(b.dy-cy, b.dx-cx)));
    final path = Path()..moveTo(pts[0].dx, pts[0].dy)..lineTo(pts[1].dx, pts[1].dy)..lineTo(pts[2].dx, pts[2].dy)..lineTo(pts[3].dx, pts[3].dy)..close();
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
