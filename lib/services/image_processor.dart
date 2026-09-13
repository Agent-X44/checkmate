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

// [LABEL: Request Models]

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
  final SendPort? replyPort; // Made optional for Isolate.run compatibility
  final double stripHeightMultiplier;
  final Rect? customSetRegion;
  final List<Offset>? customSetBubbles;
  final QrData? expectedQr;

  OmrRequest({
    required this.bytes,
    required this.corners,
    required this.template,
    this.replyPort,
    this.stripHeightMultiplier = 1.2,
    this.customSetRegion,
    this.customSetBubbles,
    this.expectedQr,
  });
}

/// Response containing detection results and optional debug imagery.
class ScanResponse {
  final bool foundPaper;
  final List<double>? corners; // Normalized coordinates [x1, y1, ...]
  final Uint8List? debugImage;
  final QrData? detectedQr;
  final List<double>? qrCorners; // Normalized QR corners [x0, y0, x1, y1, x2, y2, x3, y3]

  ScanResponse({
    required this.foundPaper,
    this.corners,
    this.debugImage,
    this.detectedQr,
    this.qrCorners,
  });
}

/// [LABEL: Memory Management]
/// Helper class to track and safely dispose OpenCV objects to prevent FFI memory leaks.
/// Ensures that even if an exception is thrown in the middle of a CV pipeline,
/// native memory is correctly freed.
class CvPool {
  final List<dynamic> _objects = [];

  T add<T>(T obj) {
    _objects.add(obj);
    return obj;
  }

  void disposeAll() {
    for (var obj in _objects) {
      try {
        if (obj is cv.Mat) {
           if (!obj.isEmpty) obj.dispose();
        } else if (obj is cv.VecPoint) {
           if (obj.isNotEmpty) obj.dispose();
        } else {
           // ignore: avoid_dynamic_calls
           obj.dispose();
        }
      } catch (_) {}
    }
    _objects.clear();
  }
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

  /// [LABEL: Future Architecture Model - Isolate.run]
  /// Spawns a temporary isolate specifically for processing one high-res image.
  /// This ensures the live camera feed isolate is NEVER blocked by heavy OMR tasks,
  /// implementing true parallelism and preventing UI jank.
  static Future<ProcessedSheet?> processOmr(OmrRequest request) async {
    return Isolate.run(() {
      return _processOmrInternal(request);
    });
  }

  /// [LABEL: Architecture - Live Stream Worker]
  /// Background worker supporting live detection (30fps camera feed).
  static void edgeDetectionWorker(SendPort mainSendPort) {
    debugPrint("OMR ISOLATE: Worker started");
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is ScanRequest) {
        _handleLiveScan(message);
      } else if (message is OmrRequest) {
        debugPrint("OMR ISOLATE: Received high-res request (legacy path)");
        final result = _processOmrInternal(message);
        message.replyPort?.send(result);
      }
    });
  }

  static void _handleLiveScan(ScanRequest message) {
    final pool = CvPool();
    try {
      // 1. [LABEL: Data Ingestion] Mat Creation & Row Stride Handling
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
        mat = pool.add(cv.Mat.fromList(
            message.height, message.width, cv.MatType.CV_8UC1, cleanBytes));
      } else {
        mat = pool.add(cv.Mat.fromList(
            message.height, message.width, cv.MatType.CV_8UC1, message.bytes));
      }

      // 2. [LABEL: Optimization] Keep a high-resolution QR search path for monitor-sized codes.
      // Some QR codes are still legible at ~800px, but large monitor-rendered codes need a second
      // pass at a higher resolution so the detector does not smear or lose the quiet zone.
      const double targetWidth = 1200.0;
      final double resizeScale = targetWidth / message.width;
      final int targetHeight = (message.height * resizeScale).toInt();
      final smallMat = pool.add(cv.resize(mat, (targetWidth.toInt(), targetHeight)));

      var processedMat = smallMat;

      if (message.rotationIndex == 1) {
        processedMat = pool.add(cv.rotate(smallMat, cv.ROTATE_90_CLOCKWISE));
      } else if (message.rotationIndex == 2) {
        processedMat = pool.add(cv.rotate(smallMat, cv.ROTATE_180));
      } else if (message.rotationIndex == 3) {
        processedMat = pool.add(cv.rotate(smallMat, cv.ROTATE_90_COUNTERCLOCKWISE));
      }

      final int finalW = processedMat.width;
      final int finalH = processedMat.height;

      // 3. [LABEL: CV Pipeline] Aggressive Noise Suppression
      final blurred = pool.add(cv.gaussianBlur(processedMat, (15, 15), 3.0));
      final edged = pool.add(cv.canny(blurred, message.cannyThreshold1, message.cannyThreshold2));

      final kernel = pool.add(cv.getStructuringElement(cv.MORPH_RECT, (9, 9)));
      final closed = pool.add(cv.morphologyEx(edged, cv.MORPH_CLOSE, kernel));
      final dilated = pool.add(cv.dilate(closed, kernel));

      // 4. [LABEL: CV Pipeline] Contour Analysis for Paper Edge Detection
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
          final approx = pool.add(cv.approxPolyDP(bestContour, 0.02 * perimeter, true));

          final double imgArea = (finalW * finalH).toDouble();

          if (maxArea > (imgArea * message.sensitivity) && approx.length == 4) {
            // Calculate aspect ratio of the 4 corners to distinguish real A4 paper from square dialog boxes
            final pts = approx.toList();
            final d01 = math.sqrt(math.pow(pts[0].x - pts[1].x, 2) + math.pow(pts[0].y - pts[1].y, 2));
            final d12 = math.sqrt(math.pow(pts[1].x - pts[2].x, 2) + math.pow(pts[1].y - pts[2].y, 2));
            final d23 = math.sqrt(math.pow(pts[2].x - pts[3].x, 2) + math.pow(pts[2].y - pts[3].y, 2));
            final d30 = math.sqrt(math.pow(pts[3].x - pts[0].x, 2) + math.pow(pts[3].y - pts[0].y, 2));

            final sideA = (d01 + d23) / 2.0;
            final sideB = (d12 + d30) / 2.0;

            final maxSide = math.max(sideA, sideB);
            final minSide = math.min(sideA, sideB);

            if (minSide > 0) {
              final paperRatio = maxSide / minSide;
              // A4 paper aspect ratio is ~1.41. Ratios between 1.20 and 1.85 are valid paper sheets.
              // Square dialog popups (ratio ~1.0) will be ignored as paper sheets!
              if (paperRatio >= 1.20 && paperRatio <= 1.85) {
                foundPaper = true;
                paperCorners = [];
                for (var i = 0; i < approx.length; i++) {
                  paperCorners.add(approx[i].x.toDouble() / finalW);
                  paperCorners.add(approx[i].y.toDouble() / finalH);
                }
              }
            }
          }
        }
      }

      // [LABEL: Feature Extraction] Real-time QR detection on the full live frame and the
      // high-resolution fallback. This is crucial when a QR occupies a large portion of a monitor
      // and the fiber of the phone camera sees glare, scanlines, or partial tilt.
      final qrResult = QrDetectionService.detectWithCorners(processedMat, fastMode: false);
      final rawFrameQr = qrResult == null ? QrDetectionService.detectEntireImage(mat) : null;

      message.replyPort.send(ScanResponse(
        foundPaper: foundPaper,
        corners: paperCorners,
        debugImage: debugBytes,
        detectedQr: qrResult?.data ?? rawFrameQr,
        qrCorners: qrResult?.corners,
      ));

    } catch (e, stack) {
      debugPrint("LIVE SCAN ISOLATE ERROR: $e\n$stack");
      message.replyPort.send(ScanResponse(foundPaper: false));
    } finally {
      // [LABEL: Cleanup] Prevent FFI Memory Leaks
      pool.disposeAll();
    }
  }

  /// Production-grade fiducial detection using Centroid analysis.
  static List<cv.Point> _detectGlobalFiducials(cv.Mat colorSheet) {
    if (colorSheet.isEmpty) return [];

    final pool = CvPool();
    try {
      final gray = pool.add(cv.cvtColor(colorSheet, cv.COLOR_BGR2GRAY));
      final blurred = pool.add(cv.gaussianBlur(gray, (5, 5), 1.5));

      final int w = gray.width;
      final int h = gray.height;

      final List<cv.Rect> zones = [
        cv.Rect(0, 0, (w * 0.30).toInt(), (h * 0.30).toInt()), // TL
        cv.Rect((w * 0.70).toInt(), 0, (w * 0.30).toInt(), (h * 0.30).toInt()), // TR
        cv.Rect((w * 0.70).toInt(), (h * 0.70).toInt(), (w * 0.30).toInt(), (h * 0.30).toInt()), // BR
        cv.Rect(0, (h * 0.70).toInt(), (w * 0.30).toInt(), (h * 0.30).toInt()), // BL
      ];

      final List<cv.Point> finalPoints = [];

      for (int zoneIdx = 0; zoneIdx < zones.length; zoneIdx++) {
        final zone = zones[zoneIdx];
        final zoneMat = pool.add(blurred.region(zone));

        cv.Mat binary = pool.add(cv.Mat.empty());
        binary = pool.add(cv.adaptiveThreshold(zoneMat, 255,
            cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 51, 10));
        
        var (contours, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
        
        if (contours.isEmpty) {
          final (_, b2) = cv.threshold(zoneMat, 100, 255, cv.THRESH_BINARY_INV);
          binary = pool.add(b2);
          final (c2, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
          contours = c2;
        }

        cv.Point? bestCentroid;
        double bestScore = -1.0;

        for (int i = 0; i < contours.length; i++) {
          final area = cv.contourArea(contours[i]);
          final perimeter = cv.arcLength(contours[i], true);
          if (perimeter < 10) continue;

          final double circularity = (4 * 3.14159 * area) / (perimeter * perimeter);

          if (area > 200 && area < (zone.width * zone.height * 0.2)) {
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
        }
      }

      return finalPoints.length == 4 ? finalPoints : [];
    } finally {
      pool.disposeAll();
    }
  }

  /// Internal isolated process for High-Res OMR
  static ProcessedSheet? _processOmrInternal(OmrRequest message) {
    final pool = CvPool();
    try {
      final mat = pool.add(cv.imdecode(message.bytes, cv.IMREAD_COLOR));
      if (mat.isEmpty) {
        return null;
      }

      if (message.expectedQr != null) {
        final isInvite = message.expectedQr!.sheetIdentifier.contains("checkmate://join") || 
                         (RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(message.expectedQr!.sheetIdentifier.toUpperCase()) && !message.expectedQr!.sheetIdentifier.toUpperCase().contains("CM50"));
        if (isInvite) {
           debugPrint("OMR: Bypassing OMR for Course Invitation -> ${message.expectedQr!.sheetIdentifier}");
           return ProcessedSheet(
             warpedImage: message.bytes,
             thresholdImage: message.bytes,
             answerRegion: message.bytes,
             questionImages: [],
             results: [],
             qrData: message.expectedQr,
             detectedSet: "SET A",
             templateName: message.template.name,
           );
        }
      }

      final rawImageQr = QrDetectionService.detectEntireImage(mat);
      if (rawImageQr != null && rawImageQr.sheetIdentifier.isNotEmpty && rawImageQr.sheetIdentifier != "UNKNOWN") {
        debugPrint("OMR: Found QR on raw unwarped image -> ${rawImageQr.sheetIdentifier}");
        return ProcessedSheet(
          warpedImage: message.bytes,
          thresholdImage: message.bytes,
          answerRegion: message.bytes,
          questionImages: [],
          results: [],
          qrData: rawImageQr,
          detectedSet: "SET A",
          templateName: message.template.name,
        );
      }

      final int matW = mat.width;
      final int matH = mat.height;

      cv.VecPoint rawCorners;
      if (message.corners.isEmpty || message.corners.length < 8) {
        rawCorners = pool.add(cv.VecPoint.fromList([
          cv.Point(0, 0),
          cv.Point(matW, 0),
          cv.Point(matW, matH),
          cv.Point(0, matH),
        ]));
      } else {
        rawCorners = pool.add(cv.VecPoint.fromList(
          List.generate(message.corners.length ~/ 2, (i) {
            return cv.Point(
              (message.corners[i * 2] * matW).toInt(),
              (message.corners[i * 2 + 1] * matH).toInt(),
            );
          }),
        ));
      }

      final int targetWidth = message.template.targetWidth;
      final double aspectRatio = message.template.paperAspectRatio;
      final orderedCorners = pool.add(PerspectiveService.orderPoints(rawCorners));
      
      final double widthBottom = math.sqrt(math.pow(orderedCorners[2].x - orderedCorners[3].x, 2) + math.pow(orderedCorners[2].y - orderedCorners[3].y, 2));
      final double widthTop = math.sqrt(math.pow(orderedCorners[1].x - orderedCorners[0].x, 2) + math.pow(orderedCorners[1].y - orderedCorners[0].y, 2));
      final double heightRight = math.sqrt(math.pow(orderedCorners[1].y - orderedCorners[2].y, 2) + math.pow(orderedCorners[1].x - orderedCorners[2].x, 2));
      final double heightLeft = math.sqrt(math.pow(orderedCorners[0].y - orderedCorners[3].y, 2) + math.pow(orderedCorners[0].x - orderedCorners[3].x, 2));
      final double finalRatio = (aspectRatio > 0.1) ? aspectRatio : (math.max(widthBottom, widthTop) / math.max(heightRight, heightLeft));
      final int targetHeight = (targetWidth / finalRatio).toInt();

      final destPointsPadded = pool.add(PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.08));
      final mFwd = pool.add(cv.getPerspectiveTransform(orderedCorners, destPointsPadded));
      var warped = pool.add(cv.warpPerspective(mat, mFwd, (targetWidth, targetHeight)));

      final globalFiducials = _detectGlobalFiducials(warped);
      if (globalFiducials.length == 4) {
        debugPrint("OMR: Locked onto 4 fiducials. Snapping to perfect grid...");
        final mRev = pool.add(cv.getPerspectiveTransform(destPointsPadded, orderedCorners));
        final mappedFiducials = PerspectiveService.transformPoints(globalFiducials, mRev);
        final destPointsExact = pool.add(PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.0));
        final finalCorners = pool.add(cv.VecPoint.fromList(mappedFiducials));
        final finalOrdered = pool.add(PerspectiveService.orderPoints(finalCorners));
        final mFinal = pool.add(cv.getPerspectiveTransform(finalOrdered, destPointsExact));
        
        warped = pool.add(cv.warpPerspective(mat, mFinal, (targetWidth, targetHeight)));
      } else {
        debugPrint("OMR: Square markers not found (${globalFiducials.length}/4). Using fallback crop.");
        final destPointsExact = pool.add(PerspectiveService.getDestPoints(targetWidth, targetHeight, 0.0));
        final mFinal = pool.add(cv.getPerspectiveTransform(orderedCorners, destPointsExact));
        
        warped = pool.add(cv.warpPerspective(mat, mFinal, (targetWidth, targetHeight)));
      }

      QrData? qrData;
      BubbleSheetTemplate activeTemplate = message.template;

      qrData = QrDetectionService.detectEntireImage(mat);

      if (qrData == null || qrData.examCode == "UNKNOWN") {
        final warpedQr = QrDetectionService.detectEntireImage(warped);
        if (warpedQr != null && warpedQr.examCode != "UNKNOWN") {
          qrData = warpedQr;
        }
      }

      if ((qrData == null || qrData.examCode == "UNKNOWN") && activeTemplate.qrRegion != null) {
        final regionalQr = QrDetectionService.detectQr(warped, activeTemplate.qrRegion!);
        if (regionalQr != null && regionalQr.examCode != "UNKNOWN") {
          qrData = regionalQr;
        }
      }

      if (qrData == null || qrData.examCode == "UNKNOWN") {
        final broadQr = QrDetectionService.searchBroad(warped);
        if (broadQr != null && broadQr.examCode != "UNKNOWN") {
          qrData = broadQr;
        }
      }

      if (qrData == null || qrData.examCode == "UNKNOWN") {
        try {
          final int targetH = (mat.height * (800.0 / mat.width)).toInt();
          final smallMat = pool.add(cv.resize(mat, (800, targetH)));
          final smallQr = QrDetectionService.detectEntireImage(smallMat);
          if (smallQr != null && smallQr.examCode != "UNKNOWN") {
            qrData = smallQr;
          }
        } catch (_) {}
      }

      if (qrData != null) {
        if (qrData.templateName == 'Standard 50 Questions' || qrData.examCode.startsWith("CM50")) {
          activeTemplate = Standard50QuestionsTemplate();
        } else if (qrData.templateName?.contains("5 Questions") == true || qrData.examCode.contains("PY5")) {
          activeTemplate = PyImageSearch5Template();
        }
        
        if (qrData.examCode == "UNKNOWN") {
          debugPrint("OMR: QR decoded failed, attempting geometric inference...");
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

      final thresholded = pool.add(ThresholdService.applyOtsuThreshold(warped));

      String? detectedSet;
      final setRegion = message.customSetRegion ?? activeTemplate.setRegion;
      final setBubbles = message.customSetBubbles ?? activeTemplate.setBubbles;

      if (setBubbles != null && setBubbles.isNotEmpty) {
        detectedSet = _detectSetFromBubbles(thresholded, setBubbles);
      } else if (setRegion != null) {
        detectedSet = _detectSetFromRegion(thresholded, setRegion);
      }

      final List<BubbleResult> results = [];
      final List<Uint8List> questionImages = [];

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
        final regionMat = pool.add(TemplateService.extractRegion(thresholded, region));
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
          pool.add(m);
          final result = BubbleDetectionService.detectFilledBubble(
            m,
            activeTemplate.choicesPerQuestion,
            isBinary: true,
            gridStart: gridStart,
            gridWidthRatio: gridWidth,
          );
          results.add(result);
          questionImages.add(Uint8List.fromList(cv.imencode(".jpg", m).$2));
        }
      }

      final warpedBytes = Uint8List.fromList(cv.imencode(".jpg", warped).$2);
      final thresholdBytes = Uint8List.fromList(cv.imencode(".jpg", thresholded).$2);
      final legacyAnswerArea = pool.add(TemplateService.extractRegion(warped, activeTemplate.answerRegions.first));
      final answerAreaBytes = Uint8List.fromList(cv.imencode(".jpg", legacyAnswerArea).$2);

      return ProcessedSheet(
        warpedImage: warpedBytes,
        thresholdImage: thresholdBytes,
        answerRegion: answerAreaBytes,
        questionImages: questionImages,
        results: results,
        qrData: qrData,
        detectedSet: detectedSet,
        templateName: activeTemplate.name,
      );
    } catch (e, stack) {
      debugPrint("OMR PROCESSOR ERROR: $e\n$stack");
      return null;
    } finally {
      pool.disposeAll();
    }
  }

  static String? _detectSetFromBubbles(cv.Mat thresholded, List<Offset> setBubbles) {
    final pool = CvPool();
    try {
      final List<double> fills = [];
      for (var p in setBubbles) {
        final int x = (p.dx * thresholded.width).toInt();
        final int y = (p.dy * thresholded.height).toInt();
        const int sz = 25;
        final r = cv.Rect((x - sz ~/ 2).clamp(0, thresholded.width - sz),
            (y - sz ~/ 2).clamp(0, thresholded.height - sz), sz, sz);
        final bubbleMat = pool.add(thresholded.region(r));
        fills.add(cv.countNonZero(bubbleMat) / (sz * sz));
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
    } finally {
      pool.disposeAll();
    }
    return null;
  }

  static String? _detectSetFromRegion(cv.Mat thresholded, Rect setRegion) {
    final pool = CvPool();
    try {
      final setMat = pool.add(TemplateService.extractRegion(thresholded, setRegion));
      final result = BubbleDetectionService.detectFilledBubble(setMat, 2,
          isBinary: true, gridStart: 0.1, gridWidthRatio: 0.8);
      if (result.answer != null) {
        return result.answer == "A" ? "SET A" : "SET B";
      }
    } catch (e) {
      debugPrint("SET REGION DETECTION ERROR: $e");
    } finally {
      pool.disposeAll();
    }
    return null;
  }
}
