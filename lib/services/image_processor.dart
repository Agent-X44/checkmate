import 'dart:isolate';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Data structure for passing camera frame data to the Isolate.
class ScanRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final SendPort replyPort;
  
  // Tuning parameters
  final double cannyThreshold1;
  final double cannyThreshold2;
  final double blurSigma;
  final double sensitivity;
  final int rotationIndex; // Added rotation to Isolate
  final bool returnDebugImage;

  ScanRequest({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.replyPort,
    this.cannyThreshold1 = 50.0,
    this.cannyThreshold2 = 150.0,
    this.blurSigma = 0.0,
    this.sensitivity = 0.02,
    this.rotationIndex = 1,
    this.returnDebugImage = false,
  });
}

class ScanResponse {
  final bool foundPaper;
  final List<double>? corners; // [x1, y1, x2, y2, ...]
  final Uint8List? debugImage;

  ScanResponse({required this.foundPaper, this.corners, this.debugImage});
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
    print("DEBUG: edgeDetectionWorker started");

    receivePort.listen((message) {
      if (message is ScanRequest) {
        try {
          // 1. Create a Mat from the Y-plane bytes (Grayscale)
          // Robustly handle padding (bytesPerRow > width) common on Android devices
          cv.Mat mat;
          if (message.bytesPerRow != message.width) {
            final cleanBytes = Uint8List(message.width * message.height);
            for (int y = 0; y < message.height; y++) {
              int start = y * message.bytesPerRow;
              cleanBytes.setRange(
                y * message.width,
                (y + 1) * message.width,
                message.bytes.getRange(start, start + message.width),
              );
            }
            mat = cv.Mat.fromList(
              message.height,
              message.width,
              cv.MatType.CV_8UC1,
              cleanBytes,
            );
          } else {
            mat = cv.Mat.fromList(
              message.height, 
              message.width, 
              cv.MatType.CV_8UC1, 
              message.bytes
            );
          }

          // Internal resize for fast processing (800px width provides good precision vs speed)
          const double targetWidth = 800.0;
          final double resizeScale = targetWidth / message.width;
          final int targetHeight = (message.height * resizeScale).toInt();
          
          final smallMat = cv.resize(mat, (targetWidth.toInt(), targetHeight));
          
          // Rotate natively in Isolate to match portrait display
          var processedMat = smallMat;
          if (message.rotationIndex == 1) { // 90 CW
             processedMat = cv.rotate(smallMat, cv.ROTATE_90_CLOCKWISE);
          } else if (message.rotationIndex == 2) { // 180
             processedMat = cv.rotate(smallMat, cv.ROTATE_180);
          } else if (message.rotationIndex == 3) { // 270 CW
             processedMat = cv.rotate(smallMat, cv.ROTATE_90_COUNTERCLOCKWISE);
          }

          final int finalW = processedMat.width;
          final int finalH = processedMat.height;

          // 2. Pre-processing: Blur and Canny Edges
          final blurred = cv.gaussianBlur(processedMat, (5, 5), message.blurSigma);
          final edged = cv.canny(blurred, message.cannyThreshold1, message.cannyThreshold2);

          // 3. Post-processing: Dilate to close gaps in contours
          final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
          final dilated = cv.dilate(edged, kernel);

          // 4. Find and approximate the largest contour
          final (contours, _) = cv.findContours(dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
          
          bool foundPaper = false;
          List<double>? paperCorners;
          Uint8List? debugBytes;

          if (message.returnDebugImage) {
            final (_, encoded) = cv.imencode(".jpg", dilated);
            debugBytes = Uint8List.fromList(encoded);
          }
          
          if (contours.isNotEmpty) {
            double maxArea = 0;
            cv.VecPoint? bestContour;
            
            for (var i = 0; i < contours.length; i++) {
              final area = cv.contourArea(contours[i]);
              if (area > maxArea) {
                maxArea = area;
                bestContour = contours[i];
              }
            }

            if (bestContour != null) {
              final double imgArea = (finalW * finalH).toDouble();
              final perimeter = cv.arcLength(bestContour, true);
              final approx = cv.approxPolyDP(bestContour, 0.02 * perimeter, true);
              
              // Return normalized coordinates (0.0 to 1.0)
              paperCorners = [];
              for (var i = 0; i < approx.length; i++) {
                paperCorners.add(approx[i].x.toDouble() / finalW);
                paperCorners.add(approx[i].y.toDouble() / finalH);
              }

              // Detection threshold: area > sensitivity % of image AND 4 corners
              if (maxArea > (imgArea * message.sensitivity) && approx.length == 4) { 
                 foundPaper = true;
              }
            }
          }

          message.replyPort.send(ScanResponse(
            foundPaper: foundPaper,
            corners: paperCorners,
            debugImage: debugBytes,
          ));
          
          mat.dispose();
          smallMat.dispose();
          if (processedMat != smallMat) processedMat.dispose();
          blurred.dispose();
          edged.dispose();
          dilated.dispose();
          kernel.dispose();
        } catch (e) {
          message.replyPort.send(false);
        }
      }
    });
  }
}
