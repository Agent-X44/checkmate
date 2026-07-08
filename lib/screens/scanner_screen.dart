import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/image_processor.dart';
import 'ai_analysis_screen.dart';

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ScannerScreen({super.key, required this.cameras});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _paperDetected = false;

  // Isolate variables
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();

  @override
  void initState() {
    super.initState();
    _startIsolate();
    _initializeCamera();
  }

  Future<void> _startIsolate() async {
    _isolate = await Isolate.spawn(ImageProcessor.edgeDetectionWorker, _mainReceivePort.sendPort);
    
    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is bool) {
        if (mounted) {
          setState(() {
            _paperDetected = message;
            _isProcessing = false;
          });
        }
      }
    });
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
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
          replyPort: _mainReceivePort.sendPort,
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
    _controller?.stopImageStream();
    _controller?.dispose();
    _isolate?.kill();
    _mainReceivePort.close();
    super.dispose();
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
          Center(
            child: CameraPreview(_controller!),
          ),
          
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.5,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _paperDetected ? Colors.greenAccent : Colors.yellowAccent.withAlpha(150), 
                  width: 3
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                   _buildCorner(Alignment.topLeft),
                   _buildCorner(Alignment.topRight),
                   _buildCorner(Alignment.bottomLeft),
                   _buildCorner(Alignment.bottomRight),
                   Center(
                    child: Text(
                      _paperDetected ? 'PAPER DETECTED' : 'Align Answer Sheet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _paperDetected ? Colors.greenAccent : Colors.white, 
                        fontSize: 16, 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ),
                ],
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
                  icon: const Icon(Icons.flash_off, color: Colors.white),
                  onPressed: () {},
                ),
                const Text(
                  'AI Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                  onPressed: () {},
                ),
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
                  _paperDetected ? 'Ready to Scan locally' : 'Local OpenCV: Detecting edges...',
                  style: TextStyle(
                    color: _paperDetected ? Colors.greenAccent : Colors.yellowAccent, 
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
                  backgroundColor: _paperDetected ? Colors.greenAccent : Colors.yellowAccent,
                  child: const Icon(Icons.camera_alt, color: Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    Color color = _paperDetected ? Colors.greenAccent : Colors.yellowAccent;
    return Align(
      alignment: alignment,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight ? BorderSide(color: color, width: 4) : BorderSide.none,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight ? BorderSide(color: color, width: 4) : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight ? BorderSide(color: color, width: 4) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
