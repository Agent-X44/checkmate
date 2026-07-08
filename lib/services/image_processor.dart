import 'dart:isolate';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Data structure for passing camera frame data to the Isolate.
class ScanRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  final SendPort replyPort;

  ScanRequest({
    required this.bytes,
    required this.width,
    required this.height,
    required this.replyPort,
  });
}

class ImageProcessor {
  
  static String getOpenCVVersion() {
    try {
      return "OpenCV (via opencv_dart)"; 
    } catch (e) {
      return "Error: $e";
    }
  }

  /// The entry point for the background Isolate worker.
  /// Uses opencv_dart API to detect paper edges in real-time.
  static void edgeDetectionWorker(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is ScanRequest) {
        try {
          // 1. Create a Mat from the Y-plane bytes
          final mat = cv.Mat.fromList(
            message.height, 
            message.width, 
            cv.MatType.CV_8UC1, 
            message.bytes
          );

          // 2. Pre-processing
          final blurred = cv.gaussianBlur(mat, (5, 5), 0);
          final edged = cv.canny(blurred, 50, 150);

          // 3. Find Contours
          // In opencv_dart, findContours returns a Record: (Contours contours, Mat hierarchy)
          final (contours, _) = cv.findContours(edged, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
          
          bool foundPaper = false;
          if (contours.isNotEmpty) {
            final double imgArea = (message.width * message.height).toDouble();
            for (var i = 0; i < contours.length; i++) {
              // Check if contour is large enough to be the answer sheet
              if (cv.contourArea(contours[i]) > (imgArea * 0.15)) {
                foundPaper = true;
                break;
              }
            }
          }

          message.replyPort.send(foundPaper);
          
          mat.dispose();
          blurred.dispose();
          edged.dispose();
        } catch (e) {
          message.replyPort.send(false);
        }
      }
    });
  }
}
