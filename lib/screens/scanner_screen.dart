import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
  
  // Production parameters (tuned for optimal detection)
  final double _cannyThresh1 = 50.0;
  final double _cannyThresh2 = 150.0;
  final double _blurSigma = 0.2;
  final double _sensitivity = 0.02;
  final int _rotationIndex = 1; // 90° CW is standard for most Android
  
  List<Offset>? _detectedCorners;
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
      _startIsolate();
      _initializeCamera();
    }
  }

  @override
  void didUpdateWidget(ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _startIsolate();
        _initializeCamera();
      } else {
        _disposeCamera();
      }
    }
  }

  void _disposeCamera() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _controller = null;
    _isolate?.kill();
    _isolate = null;
    _isInitialized = false;
    _paperDetected = false;
    _detectedCorners = null;
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
            _isProcessing = false;
            // Throttle UI updates to keep camera smooth and responsive
            if (DateTime.now().difference(_lastUIUpdate).inMilliseconds > 70) {
              setState(() {
                _paperDetected = message.foundPaper;
                if (message.corners != null) {
                  _detectedCorners = [];
                  for (var i = 0; i < message.corners!.length; i += 2) {
                    _detectedCorners!.add(Offset(message.corners![i], message.corners![i+1]));
                  }
                } else {
                  _detectedCorners = null;
                }
              });
              _lastUIUpdate = DateTime.now();
            }
          }
        }
      });
    }
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
      
      _controller!.startImageStream((CameraImage image) {
        if (_isProcessing || _isolateSendPort == null) return;

        _isProcessing = true;
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
    _disposeCamera();
    _mainReceivePort.close();
    super.dispose();
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
          // AspectRatio ensures overlay coordinates match preview dimensions exactly
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: Stack(
                children: [
                  CameraPreview(_controller!),
                  
                  // Real-time edge tracing overlay
                  if (_detectedCorners != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: EdgePainter(
                          corners: _detectedCorners!,
                          isDetected: _paperDetected,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Guide frame - subtle blue when searching, yellow when detected
          if (!_paperDetected)
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.5,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.blueAccent.withAlpha(100), 
                    width: 1
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'Align Answer Sheet',
                    style: TextStyle(color: Colors.blueAccent, fontSize: 16),
                  ),
                ),
              ),
            ),
          
          if (_paperDetected)
            const Positioned(
              top: 100,
              left: 0, right: 0,
              child: Center(
                child: Chip(
                  backgroundColor: Colors.yellowAccent,
                  label: Text('READY TO SCAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ),

          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                  onPressed: _toggleFlash,
                ),
                const Text(
                  'AI Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 48), // Keep title centered
              ],
            ),
          ),
          
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _paperDetected ? 'Ready to Scan' : 'Detecting edges...',
                  style: TextStyle(
                    color: _paperDetected ? Colors.yellowAccent : Colors.blueAccent, 
                    fontSize: 14, 
                    fontWeight: FontWeight.w500
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.large(
                  heroTag: null,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AIAnalysisScreen()),
                    );
                  },
                  backgroundColor: _paperDetected ? Colors.yellowAccent : Colors.blueAccent,
                  child: const Icon(Icons.camera_alt, color: Colors.black),
                ),
              ],
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

    // Scale normalized Isolate coordinates (0.0 to 1.0) to local canvas size
    List<Offset> transformed = corners.map((p) {
      return Offset(p.dx * size.width, p.dy * size.height);
    }).toList();

    // Prevent crossed/bow-tie polygons by sorting points clockwise
    List<Offset> sorted = _sortCorners(transformed);

    final path = Path()
      ..moveTo(sorted[0].dx, sorted[0].dy)
      ..lineTo(sorted[1].dx, sorted[1].dy)
      ..lineTo(sorted[2].dx, sorted[2].dy)
      ..lineTo(sorted[3].dx, sorted[3].dy)
      ..close();

    canvas.drawPath(path, paint);
    
    // Draw corner markers for visual precision
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
