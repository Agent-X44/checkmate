import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/qr_data.dart';
import '../models/omr/templates/py_image_search_5.dart';
import '../models/omr/templates/standard_50_questions.dart';
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
  final double stripHeightMultiplier;
  final Rect? customSetRegion;
  final List<Offset>? customSetBubbles;

  OmrRequest({
    required this.bytes,
    required this.corners,
    required this.template,
    required this.replyPort,
    this.stripHeightMultiplier = 1.2,
    this.customSetRegion,
    this.customSetBubbles,
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
    debugPrint("OMR ISOLATE: Worker started");
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is ScanRequest) {
        _handleLiveScan(message);
      } else if (message is OmrRequest) {
        debugPrint("OMR ISOLATE: Received high-res request");
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
        mat = cv.Mat.fromList(
            message.height, message.width, cv.MatType.CV_8UC1, cleanBytes);
      } else {
        mat = cv.Mat.fromList(
            message.height, message.width, cv.MatType.CV_8UC1, message.bytes);
      }

      // 2. Optimization: Downscale for FAST background processing
      // We process at 400px width for maximum performance, matching the logic of
      // capturing HD but analyzing at a lower resolution.
      const double targetWidth = 400.0;
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
      final blurred = cv.gaussianBlur(processedMat, (15, 15), 3.0);
      final edged =
          cv.canny(blurred, message.cannyThreshold1, message.cannyThreshold2);

      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
      final closed = cv.morphologyEx(edged, cv.MORPH_CLOSE, kernel);
      final dilated = cv.dilate(closed, kernel);

      // 4. Contour Analysis
      final (contours, _) =
          cv.findContours(dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

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
    } catch (e, stack) {
      debugPrint("LIVE SCAN ISOLATE ERROR: $e\n$stack");
      message.replyPort.send(ScanResponse(foundPaper: false));
    }
  }

  /// Production-grade fiducial detection using Centroid analysis.
  /// Expects solid circular marks in the 4 corners of the sheet.
  static List<cv.Point> _detectGlobalFiducials(cv.Mat colorSheet) {
    if (colorSheet.isEmpty) return [];

    final gray = cv.cvtColor(colorSheet, cv.COLOR_BGR2GRAY);
    // 1. Stabilize image with Gaussian Blur
    final blurred = cv.gaussianBlur(gray, (5, 5), 1.5);

    final int w = gray.width;
    final int h = gray.height;

    // Define 4 corner search zones (12% of sheet size)
    final List<cv.Rect> zones = [
      cv.Rect(0, 0, (w * 0.12).toInt(), (h * 0.12).toInt()), // TL
      cv.Rect(
          (w * 0.88).toInt(), 0, (w * 0.12).toInt(), (h * 0.12).toInt()), // TR
      cv.Rect((w * 0.88).toInt(), (h * 0.88).toInt(), (w * 0.12).toInt(),
          (h * 0.12).toInt()), // BR
      cv.Rect(
          0, (h * 0.88).toInt(), (w * 0.12).toInt(), (h * 0.12).toInt()), // BL
    ];

    final List<cv.Point> finalPoints = [];

    for (var zone in zones) {
      final zoneMat = blurred.region(zone);

      // 2. Local Adaptive Thresholding (Crucial for uneven lighting)
      final binary = cv.adaptiveThreshold(zoneMat, 255,
          cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 21, 5);

      final (contours, _) =
          cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      cv.Point? bestCentroid;
      double bestCircularity = 0;

      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        final perimeter = cv.arcLength(contours[i], true);
        if (perimeter == 0) continue;

        // 3. Circularity Check (Production-level filtering)
        // Formula: 4 * pi * area / (perimeter^2). 1.0 is a perfect circle.
        final double circularity =
            (4 * 3.14159 * area) / (perimeter * perimeter);

        // 4. Robust Anchor Constraints (Area must be significant but not too big)
        if (area > 80 && area < (zone.width * zone.height * 0.3)) {
          if (circularity > 0.65 && circularity > bestCircularity) {
            // 5. Centroid Calculation via Bounding Box center (Stable)
            final rect = cv.boundingRect(contours[i]);
            bestCircularity = circularity;
            bestCentroid = cv.Point(zone.x + rect.x + rect.width ~/ 2,
                zone.y + rect.y + rect.height ~/ 2);
          }
        }
      }

      if (bestCentroid != null) finalPoints.add(bestCentroid);
      zoneMat.dispose();
      binary.dispose();
      contours.dispose();
    }

    gray.dispose();
    blurred.dispose();

    return finalPoints.length == 4 ? finalPoints : [];
  }

  static void _handleOmrProcess(OmrRequest message) {
    cv.Mat? mat;
    cv.Mat? warped;
    cv.Mat? thresholded;

    try {
      // 1. Load high-res image
      mat = cv.imdecode(message.bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) {
        message.replyPort.send(null);
        return;
      }

      final int matW = mat.width;
      final int matH = mat.height;

      // 1.1 Rough perspective corners
      final rawCorners = cv.VecPoint.fromList(
        List.generate(message.corners.length ~/ 2, (i) {
          return cv.Point(
            (message.corners[i * 2] * matW).toInt(),
            (message.corners[i * 2 + 1] * matH).toInt(),
          );
        }),
      );

      // 3. Perspective Correction (Pass 1: Paper Edges with Padding)
      // Added 3% padding to ensure 4-corner square markers are NOT clipped.
      warped = PerspectiveService.warpPaper(mat, rawCorners,
          message.template.paperAspectRatio, message.template.targetWidth,
          padding: 0.03);

      rawCorners.dispose();

      // 3.1 Precision Rectification (Pass 2: 4-Corner Marks)
      final globalFiducials = _detectGlobalFiducials(warped);
      if (globalFiducials.length == 4) {
        debugPrint(
            "OMR: Locked onto 4 square marks. Snapping to perfect grid...");
        final refinedWarped = PerspectiveService.warpPaper(
            warped,
            cv.VecPoint.fromList(globalFiducials),
            message.template.paperAspectRatio,
            message.template.targetWidth,
            padding: 0.0 // Snap markers to exact corners (0.0 to 1.0)
            );
        warped.dispose();
        warped = refinedWarped;
      } else {
        debugPrint(
            "OMR: Square markers not found (${globalFiducials.length}/4). Using estimated grid.");
        // Fallback: Perform a warp with 0 padding to remove the 3% safety border
        final fallbackCorners = cv.VecPoint.fromList(
            List.generate(message.corners.length ~/ 2, (i) {
          return cv.Point(
            (message.corners[i * 2] * matW).toInt(),
            (message.corners[i * 2 + 1] * matH).toInt(),
          );
        }));
        final fallbackWarped = PerspectiveService.warpPaper(
            mat,
            fallbackCorners,
            message.template.paperAspectRatio,
            message.template.targetWidth);
        fallbackCorners.dispose();
        warped.dispose();
        warped = fallbackWarped;
      }

      // 4. QR Code Recognition
      QrData? qrData;
      BubbleSheetTemplate activeTemplate = message.template;

      try {
        final detector = cv.QRCodeDetector.empty();
        final List<Rect> qrRegions = [
          if (activeTemplate.qrRegion != null) activeTemplate.qrRegion!,
          const Rect.fromLTRB(0.6, 0.05, 0.95, 0.3), // Typical QR area
        ];

        for (final region in qrRegions) {
          final int x =
              (region.left * warped.width).toInt().clamp(0, warped.width - 1);
          final int y =
              (region.top * warped.height).toInt().clamp(0, warped.height - 1);
          final int w =
              (region.width * warped.width).toInt().clamp(1, warped.width - x);
          final int h = (region.height * warped.height)
              .toInt()
              .clamp(1, warped.height - y);

          final qrInput = warped.region(cv.Rect(x, y, w, h));
          final (text, points, _) = detector.detectAndDecode(qrInput);

          points.dispose();
          qrInput.dispose();

          if (text.isNotEmpty) {
            qrData = QrData.fromRaw(text);
            debugPrint("QR DETECTED: $text");
            if (qrData.templateName == 'Standard 50 Questions' ||
                qrData.examCode.startsWith("CM50")) {
              activeTemplate = Standard50QuestionsTemplate();
            }
            break;
          }
        }
        detector.dispose();
      } catch (e) {
        debugPrint("QR ENGINE SKIPPED: Missing Native Symbol ($e)");
      }

      // 5. Adaptive Thresholding
      thresholded = ThresholdService.applyOtsuThreshold(warped);

      // 5.0 Set Detection (New)
      String? detectedSet;
      final setRegion = message.customSetRegion ?? activeTemplate.setRegion;
      final setBubbles = message.customSetBubbles ?? activeTemplate.setBubbles;

      if (setBubbles != null && setBubbles.isNotEmpty) {
        try {
          final List<double> fills = [];
          for (var p in setBubbles) {
            final int x = (p.dx * thresholded.width).toInt();
            final int y = (p.dy * thresholded.height).toInt();
            const int sz = 25;
            final r = cv.Rect((x - sz ~/ 2).clamp(0, thresholded.width - sz),
                (y - sz ~/ 2).clamp(0, thresholded.height - sz), sz, sz);
            final bubbleMat = thresholded.region(r);
            fills.add(cv.countNonZero(bubbleMat) / (sz * sz));
            bubbleMat.dispose();
          }
          if (fills.isNotEmpty) {
            int winner = 0;
            for (int i = 1; i < fills.length; i++) {
              if (fills[i] > fills[winner]) {
                winner = i;
              }
            }
            if (fills[winner] > 0.15) {
              detectedSet = "SET ${String.fromCharCode(65 + winner)}";
            }
          }
        } catch (e) {
          debugPrint("SET BUBBLE DETECTION ERROR: $e");
        }
      } else if (setRegion != null) {
        try {
          final setMat = TemplateService.extractRegion(thresholded, setRegion);
          final result = BubbleDetectionService.detectFilledBubble(setMat, 2,
              isBinary: true, gridStart: 0.1, gridWidthRatio: 0.8);
          if (result.answer != null) {
            detectedSet = result.answer == "A" ? "SET A" : "SET B";
            debugPrint("OMR: Detected $detectedSet");
          }
          setMat.dispose();
        } catch (e) {
          debugPrint("SET REGION DETECTION ERROR: $e");
        }
      }

      // 5.1 Dynamic Column Detection (NEW: Max Area Logic)
      List<Rect> activeRegions = activeTemplate.answerRegions;

      // 5.2 Answer Region Extraction and Question Splitting
      final List<BubbleResult> results = [];
      final List<Uint8List> questionImages = [];

      // Default Calibration
      double gridStart = 0.15;
      double gridWidth = 0.82;
      int calibratedY = 60;

      if (activeTemplate is PyImageSearch5Template) {
        gridStart = PyImageSearch5Template.defaultGridStart;
        gridWidth = PyImageSearch5Template.defaultGridWidth;
        calibratedY = PyImageSearch5Template.calibratedYOffset;
      } else if (activeTemplate is Standard50QuestionsTemplate) {
        gridStart = Standard50QuestionsTemplate.defaultGridStart;
        gridWidth = Standard50QuestionsTemplate.defaultGridWidth;
        calibratedY = Standard50QuestionsTemplate.calibratedYOffset;
      }

      // Process each answer region (column)
      final int questionsPerRegion =
          (activeTemplate.totalQuestions / activeRegions.length).ceil();

      for (int i = 0; i < activeRegions.length; i++) {
        final region = activeRegions[i];
        final regionMat = TemplateService.extractRegion(thresholded, region);

        final questionsInThisRegion = (i == activeRegions.length - 1)
            ? activeTemplate.totalQuestions - (questionsPerRegion * i)
            : questionsPerRegion;

        final questionMats = TemplateService.splitQuestions(
          regionMat,
          questionsInThisRegion,
          yOffset: calibratedY,
          heightMultiplier: message.stripHeightMultiplier,
        );

        for (final m in questionMats) {
          final result = BubbleDetectionService.detectFilledBubble(
            m,
            activeTemplate.choicesPerQuestion,
            isBinary: true,
            gridStart: gridStart,
            gridWidthRatio: gridWidth,
          );
          results.add(result);

          final bytes = Uint8List.fromList(cv.imencode(".jpg", m).$2);
          questionImages.add(bytes);
          m.dispose();
        }
        regionMat.dispose();
      }

      final warpedBytes = Uint8List.fromList(cv.imencode(".jpg", warped).$2);
      final thresholdBytes =
          Uint8List.fromList(cv.imencode(".jpg", thresholded).$2);

      final legacyAnswerArea = TemplateService.extractRegion(
          warped, activeTemplate.answerRegions.first);
      final answerAreaBytes =
          Uint8List.fromList(cv.imencode(".jpg", legacyAnswerArea).$2);
      legacyAnswerArea.dispose();

      message.replyPort.send(ProcessedSheet(
        warpedImage: warpedBytes,
        thresholdImage: thresholdBytes,
        answerRegion: answerAreaBytes,
        questionImages: questionImages,
        results: results,
        qrData: qrData,
        detectedSet: detectedSet,
        templateName: activeTemplate.name,
      ));
    } catch (e, stack) {
      debugPrint("OMR PROCESSOR ERROR: $e\n$stack");
      message.replyPort.send(null);
    } finally {
      mat?.dispose();
      warped?.dispose();
      thresholded?.dispose();
    }
  }
}
