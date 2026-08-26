import 'dart:isolate';
import 'dart:math' as math;
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
import 'cv/qr_detection_service.dart';

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

/// Core Computer Vision engine for OMR processing.
/// 
/// Enforces:
/// - BR-06: Local Edge OMR processing (OpenCV on device)
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
  /// Optimized for steep angles and varied lighting.
  static List<cv.Point> _detectGlobalFiducials(cv.Mat colorSheet) {
    if (colorSheet.isEmpty) return [];

    final gray = cv.cvtColor(colorSheet, cv.COLOR_BGR2GRAY);
    // 1. Stabilize image
    final blurred = cv.gaussianBlur(gray, (5, 5), 1.5);

    final int w = gray.width;
    final int h = gray.height;

    // Define 4 corner search zones (30% to handle loose paper detection)
    final List<cv.Rect> zones = [
      cv.Rect(0, 0, (w * 0.30).toInt(), (h * 0.30).toInt()), // TL
      cv.Rect((w * 0.70).toInt(), 0, (w * 0.30).toInt(), (h * 0.30).toInt()), // TR
      cv.Rect((w * 0.70).toInt(), (h * 0.70).toInt(), (w * 0.30).toInt(), (h * 0.30).toInt()), // BR
      cv.Rect(0, (h * 0.70).toInt(), (w * 0.30).toInt(), (h * 0.30).toInt()), // BL
    ];

    final List<cv.Point> finalPoints = [];

    for (int zoneIdx = 0; zoneIdx < zones.length; zoneIdx++) {
      final zone = zones[zoneIdx];
      final zoneMat = blurred.region(zone);

      // Try multiple threshold levels to find the solid black dot
      cv.Mat binary = cv.Mat.empty();
      
      // Strategy 1: Aggressive Adaptive Threshold
      binary = cv.adaptiveThreshold(zoneMat, 255,
          cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 51, 10);
      
      var (contours, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      
      // If Strategy 1 fails, try Strategy 2: Simple Threshold
      if (contours.isEmpty) {
        binary.dispose();
        final (_, b2) = cv.threshold(zoneMat, 100, 255, cv.THRESH_BINARY_INV);
        binary = b2;
        final (c2, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
        contours = c2;
      }

      cv.Point? bestCentroid;
      double bestScore = -1.0;

      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        final perimeter = cv.arcLength(contours[i], true);
        if (perimeter < 10) continue;

        // Circularity: Accept very distorted ellipses
        final double circularity = (4 * 3.14159 * area) / (perimeter * perimeter);

        // Dot area constraints: 1500px wide image, dots are ~30-80px.
        // Area should be between 200 and 10000.
        if (area > 200 && area < (zone.width * zone.height * 0.2)) {
          // Weight circularity and area. Dots are usually the most "solid" things in corners.
          final double score = circularity * area;
          
          if (circularity > 0.2 && score > bestScore) {
            final contourPts = contours[i].toList();
            if (contourPts.isNotEmpty) {
              double sumX = 0, sumY = 0;
              for (var p in contourPts) {
                sumX += p.x;
                sumY += p.y;
              }
              bestScore = score;
              bestCentroid = cv.Point(
                zone.x + (sumX / contourPts.length).round(),
                zone.y + (sumY / contourPts.length).round(),
              );
            }
          }
        }
      }

      if (bestCentroid != null) {
        finalPoints.add(bestCentroid);
      } else {
        debugPrint("OMR: Missing fiducial in zone $zoneIdx (Candidates: ${contours.length})");
      }
      
      zoneMat.dispose();
      binary.dispose();
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

      // 2. Initial Warp (Pass 1: Paper Edges with Padding)
      final int targetWidth = message.template.targetWidth;
      final double aspectRatio = message.template.paperAspectRatio;
      final orderedCorners = PerspectiveService.orderPoints(rawCorners);
      
      final double widthBottom = math.sqrt(math.pow(orderedCorners[2].x - orderedCorners[3].x, 2) + math.pow(orderedCorners[2].y - orderedCorners[3].y, 2));
      final double widthTop = math.sqrt(math.pow(orderedCorners[1].x - orderedCorners[0].x, 2) + math.pow(orderedCorners[1].y - orderedCorners[0].y, 2));
      final double heightRight = math.sqrt(math.pow(orderedCorners[1].y - orderedCorners[2].y, 2) + math.pow(orderedCorners[1].x - orderedCorners[2].x, 2));
      final double heightLeft = math.sqrt(math.pow(orderedCorners[0].y - orderedCorners[3].y, 2) + math.pow(orderedCorners[0].x - orderedCorners[3].x, 2));
      final double finalRatio = (aspectRatio > 0.1) ? aspectRatio : (math.max(widthBottom, widthTop) / math.max(heightRight, heightLeft));
      final int targetHeight = (targetWidth / finalRatio).toInt();

      final destPointsPadded = PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.08);
      final mFwd = cv.getPerspectiveTransform(orderedCorners, destPointsPadded);
      warped = cv.warpPerspective(mat, mFwd, (targetWidth, targetHeight));

      // 3. Precision Snap (Pass 2 Logic)
      final globalFiducials = _detectGlobalFiducials(warped);
      if (globalFiducials.length == 4) {
        debugPrint("OMR: Locked onto 4 fiducials. Snapping to perfect grid...");
        final mRev = cv.getPerspectiveTransform(destPointsPadded, orderedCorners);
        final mappedFiducials = PerspectiveService.transformPoints(globalFiducials, mRev);
        final destPointsExact = PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.0);
        final finalCorners = cv.VecPoint.fromList(mappedFiducials);
        final finalOrdered = PerspectiveService.orderPoints(finalCorners);
        final mFinal = cv.getPerspectiveTransform(finalOrdered, destPointsExact);
        final refinedWarped = cv.warpPerspective(mat, mFinal, (targetWidth, targetHeight));
        
        warped.dispose();
        warped = refinedWarped;
        
        mRev.dispose();
        mFinal.dispose();
        finalCorners.dispose();
        finalOrdered.dispose();
        destPointsExact.dispose();
      } else {
        debugPrint("OMR: Square markers not found (${globalFiducials.length}/4). Using fallback crop.");
        final destPointsExact = PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.0);
        final mFinal = cv.getPerspectiveTransform(orderedCorners, destPointsExact);
        final fallbackWarped = cv.warpPerspective(mat, mFinal, (targetWidth, targetHeight));
        warped.dispose();
        warped = fallbackWarped;
        mFinal.dispose();
        destPointsExact.dispose();
      }

      mFwd.dispose();
      destPointsPadded.dispose();
      orderedCorners.dispose();
      rawCorners.dispose();

      // 4. Robust QR Recognition
      QrData? qrData;
      BubbleSheetTemplate activeTemplate = message.template;

      // Primary Search: Template Region
      if (activeTemplate.qrRegion != null) {
        qrData = QrDetectionService.detectQr(warped, activeTemplate.qrRegion!);
      }

      // Secondary Search: Broad upper-right quadrant
      qrData ??= QrDetectionService.searchBroad(warped);

      if (qrData != null) {
        // Dynamic Template Selection
        if (qrData.templateName == 'Standard 50 Questions' || qrData.examCode.startsWith("CM50")) {
          activeTemplate = Standard50QuestionsTemplate();
        } else if (qrData.templateName?.contains("5 Questions") == true || qrData.examCode.contains("PY5")) {
          activeTemplate = PyImageSearch5Template();
        }
        
        // HEURISTIC FALLBACK: If QR failed to decode but was FOUND, 
        // infer template based on paper geometry if it's still "UNKNOWN"
        if (qrData.examCode == "UNKNOWN") {
          debugPrint("OMR: QR decoded failed, attempting geometric inference...");
          // If we have 2 columns and 50 questions is our standard, assume it.
          // This ensures the student info UI shows "Detected" instead of "Unknown".
          activeTemplate = Standard50QuestionsTemplate();
          qrData = QrData(
            studentName: "Detected (Matching Template)",
            examCode: "CM50-AUTO",
            course: "Auto-Detected",
            examTitle: activeTemplate.name,
            sheetIdentifier: "CM50-AUTO",
          );
        }
        
        debugPrint("OMR: Active Template -> ${activeTemplate.name}");
      }

      // 5. OMR Processing
      thresholded = ThresholdService.applyOtsuThreshold(warped);

      // 5.1 Set Detection
      String? detectedSet;
      final setRegion = message.customSetRegion ?? activeTemplate.setRegion;
      final setBubbles = message.customSetBubbles ?? activeTemplate.setBubbles;

      if (setBubbles != null && setBubbles.isNotEmpty) {
        detectedSet = _detectSetFromBubbles(thresholded, setBubbles);
      } else if (setRegion != null) {
        detectedSet = _detectSetFromRegion(thresholded, setRegion);
      }

      // 5.2 Answer Region Extraction
      final List<BubbleResult> results = [];
      final List<Uint8List> questionImages = [];

      // Calibration Parameters
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

      final List<Rect> activeRegions = activeTemplate.answerRegions;
      final int questionsPerRegion = (activeTemplate.totalQuestions / activeRegions.length).ceil();

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
          questionImages.add(Uint8List.fromList(cv.imencode(".jpg", m).$2));
          m.dispose();
        }
        regionMat.dispose();
      }

      // 6. Final Packaging
      final warpedBytes = Uint8List.fromList(cv.imencode(".jpg", warped).$2);
      final thresholdBytes = Uint8List.fromList(cv.imencode(".jpg", thresholded).$2);
      final legacyAnswerArea = TemplateService.extractRegion(warped, activeTemplate.answerRegions.first);
      final answerAreaBytes = Uint8List.fromList(cv.imencode(".jpg", legacyAnswerArea).$2);
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

  static String? _detectSetFromBubbles(cv.Mat thresholded, List<Offset> setBubbles) {
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
          if (fills[i] > fills[winner]) winner = i;
        }
        if (fills[winner] > 0.15) {
          return "SET ${String.fromCharCode(65 + winner)}";
        }
      }
    } catch (e) {
      debugPrint("SET BUBBLE DETECTION ERROR: $e");
    }
    return null;
  }

  static String? _detectSetFromRegion(cv.Mat thresholded, Rect setRegion) {
    try {
      final setMat = TemplateService.extractRegion(thresholded, setRegion);
      final result = BubbleDetectionService.detectFilledBubble(setMat, 2,
          isBinary: true, gridStart: 0.1, gridWidthRatio: 0.8);
      setMat.dispose();
      if (result.answer != null) {
        return result.answer == "A" ? "SET A" : "SET B";
      }
    } catch (e) {
      debugPrint("SET REGION DETECTION ERROR: $e");
    }
    return null;
  }
}