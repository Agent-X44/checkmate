import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/templates/py_image_search_5.dart';
import 'cv/perspective_service.dart';
import 'cv/threshold_service.dart';
import 'cv/template_service.dart';
import 'cv/bubble_detection_service.dart';

/// Data structure for passing camera frame data and tuning parameters to the Isolate.
class ScanRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final SendPort replyPort;
  
  final double cannyThreshold1;
  final double cannyThreshold2;
  final double blurSigma;
  final double sensitivity;
  final int rotationIndex;
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

/// Request for full high-res OMR processing.
class OmrRequest {
  final Uint8List bytes;
  final List<double> corners; // Normalized corners from live detection
  final BubbleSheetTemplate template;
  final SendPort replyPort;

  OmrRequest({
    required this.bytes,
    required this.corners,
    required this.template,
    required this.replyPort,
  });
}

/// Response containing detection results and optional debug imagery.
class ScanResponse {
  final bool foundPaper;
  final List<double>? corners; // Normalized coordinates [x1, y1, ...]
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

  /// Background worker supporting both live detection and high-res OMR processing.
  static void edgeDetectionWorker(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is ScanRequest) {
        _handleLiveScan(message);
      } else if (message is OmrRequest) {
        _handleOmrProcess(message);
      }
    });
  }

  static void _handleLiveScan(ScanRequest message) {
    try {
      // 1. Mat Creation & Row Stride Handling
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
        mat = cv.Mat.fromList(message.height, message.width, cv.MatType.CV_8UC1, cleanBytes);
      } else {
        mat = cv.Mat.fromList(message.height, message.width, cv.MatType.CV_8UC1, message.bytes);
      }

      // 2. Optimization: Resize and Rotate
      const double targetWidth = 800.0;
      final double resizeScale = targetWidth / message.width;
      final int targetHeight = (message.height * resizeScale).toInt();
      final smallMat = cv.resize(mat, (targetWidth.toInt(), targetHeight));
      
      var processedMat = smallMat;
      if (message.rotationIndex == 1) {
         processedMat = cv.rotate(smallMat, cv.ROTATE_90_CLOCKWISE);
      } else if (message.rotationIndex == 2) {
         processedMat = cv.rotate(smallMat, cv.ROTATE_180);
      } else if (message.rotationIndex == 3) {
         processedMat = cv.rotate(smallMat, cv.ROTATE_90_COUNTERCLOCKWISE);
      }

      final int finalW = processedMat.width;
      final int finalH = processedMat.height;

      // 3. Computer Vision Pipeline: Aggressive Noise Suppression
      // Sharp images have too much texture noise. We blur heavily to find the paper outline.
      final blurred = cv.gaussianBlur(processedMat, (7, 7), message.blurSigma);
      final edged = cv.canny(blurred, message.cannyThreshold1, message.cannyThreshold2);
      
      // Use Morphological Closing to consolidate the paper outline edges
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      final closed = cv.morphologyEx(edged, cv.MORPH_CLOSE, kernel);
      final dilated = cv.dilate(closed, kernel);

      // 4. Contour Analysis
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
          final perimeter = cv.arcLength(bestContour, true);
          final approx = cv.approxPolyDP(bestContour, 0.02 * perimeter, true);
          
          final double imgArea = (finalW * finalH).toDouble();

          // STRICT QUADRILATERAL CHECK: Only return corners IF it is a 4-point shape
          if (maxArea > (imgArea * message.sensitivity) && approx.length == 4) { 
             foundPaper = true;
             paperCorners = [];
             for (var i = 0; i < approx.length; i++) {
               paperCorners.add(approx[i].x.toDouble() / finalW);
               paperCorners.add(approx[i].y.toDouble() / finalH);
             }
          }
        }
      }

      message.replyPort.send(ScanResponse(
        foundPaper: foundPaper,
        corners: paperCorners,
        debugImage: debugBytes,
      ));
      
      // Resource Cleanup
      mat.dispose();
      smallMat.dispose();
      if (processedMat != smallMat) processedMat.dispose();
      blurred.dispose();
      edged.dispose();
      closed.dispose();
      dilated.dispose();
      kernel.dispose();
    } catch (e) {
      message.replyPort.send(false);
    }
  }

  static void _handleOmrProcess(OmrRequest message) {
    try {
      // 1. Load high-res image
      final mat = cv.imdecode(message.bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) {
        message.replyPort.send(null);
        return;
      }
      
      // 2. Map normalized corners to high-res coordinates
      final int matW = mat.width;
      final int matH = mat.height;
      
      final corners = cv.VecPoint.fromList(
        List.generate(message.corners.length ~/ 2, (i) {
          return cv.Point(
            (message.corners[i * 2] * matW).toInt(),
            (message.corners[i * 2 + 1] * matH).toInt(),
          );
        }),
      );

      // 3. Perspective Correction
      final warped = PerspectiveService.warpPaper(
        mat, 
        corners, 
        message.template.paperAspectRatio, 
        message.template.targetWidth
      );
      
      if (warped.isEmpty) {
        mat.dispose();
        corners.dispose();
        message.replyPort.send(null);
        return;
      }

      // 4. Adaptive Thresholding (Lighting Compensation happens inside)
      final thresholded = ThresholdService.applyAdaptiveThreshold(warped);

      // 5. Answer Region Extraction
      final answerArea = TemplateService.extractAnswerRegion(warped, message.template);
      final answerAreaBinary = TemplateService.extractAnswerRegion(thresholded, message.template);
      
      // Final Precision Grid Calibration (PyImageSearch)
      double gridStart = 0.15; // Global Default
      double gridWidth = 0.82; // Global Default
      int calibratedY = 60;    // Global Default

      if (message.template is PyImageSearch5Template) {
        gridStart = PyImageSearch5Template.defaultGridStart;
        gridWidth = PyImageSearch5Template.defaultGridWidth;
        calibratedY = PyImageSearch5Template.calibratedYOffset;
      }

      final questionMats = TemplateService.splitQuestions(
        answerAreaBinary, 
        message.template,
        yOffset: calibratedY,
      );
      
      final List<BubbleResult> results = [];
      final List<Uint8List> questionImages = [];

      for (final m in questionMats) {
        final result = BubbleDetectionService.detectFilledBubble(
          m, 
          message.template.choicesPerQuestion,
          isBinary: true,
          gridStart: gridStart,
          gridWidthRatio: gridWidth,
        );
        results.add(result);

        final bytes = Uint8List.fromList(cv.imencode(".jpg", m).$2);
        questionImages.add(bytes);
        m.dispose();
      }

      final warpedBytes = Uint8List.fromList(cv.imencode(".jpg", warped).$2);
      final thresholdBytes = Uint8List.fromList(cv.imencode(".jpg", thresholded).$2);
      final answerAreaBytes = Uint8List.fromList(cv.imencode(".jpg", answerArea).$2);

      message.replyPort.send(ProcessedSheet(
        warpedImage: warpedBytes,
        thresholdImage: thresholdBytes,
        answerRegion: answerAreaBytes,
        questionImages: questionImages,
        results: results,
      ));

      // Cleanup
      mat.dispose();
      corners.dispose();
      warped.dispose();
      thresholded.dispose();
      answerArea.dispose();
      answerAreaBinary.dispose();
    } catch (e) {
      debugPrint("OMR PROCESSOR ERROR: $e");
      message.replyPort.send(null);
    }
  }
}
