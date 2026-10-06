import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/qr_data.dart';
import '../models/omr/templates/py_image_search_5.dart';
import '../models/omr/templates/standard_50_questions.dart';
import 'cv/perspective_service.dart';
import 'cv/sheet_alignment_service.dart';
import 'cv/fiducial_geometry.dart';
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
  final int scanSession;

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
    this.scanSession = 0,
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
  final List<double> corners; // Preview overlay only; capture is re-detected
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

/// No deterministic item grading may run on an unverified alignment.
class SheetAlignmentException implements Exception {
  const SheetAlignmentException();

  @override
  String toString() => 'Could not align the answer sheet. Keep all four corner '
      'circles visible, move the camera closer to facing the sheet, and retake.';
}

/// Response containing detection results and optional debug imagery.
class ScanResponse {
  final bool foundPaper;
  final int scanSession;
  final List<double>? corners; // Normalized coordinates [x1, y1, ...]
  final Uint8List? debugImage;
  final QrData? detectedQr;
  final List<double>? qrCorners; // Normalized QR corners [x0, y0, x1, y1, x2, y2, x3, y3]

  ScanResponse({
    required this.foundPaper,
    this.scanSession = 0,
    this.corners,
    this.debugImage,
    this.detectedQr,
    this.qrCorners,
  });
}

/// [LABEL: Memory Management]
/// Helper class to track OpenCV objects.
/// OpenCV Dart 2.0+ uses automatic memory management via Finalizers.
/// Manual disposal can cause double-free crashes during heavy GC.
class CvPool {
  T add<T>(T obj) {
    return obj;
  }

  void disposeAll() {
    // No-op: Let Dart Garbage Collector and OpenCV Finalizers handle memory.
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
          if (start + message.width <= message.bytes.length) {
            cleanBytes.setRange(
              y * message.width,
              (y + 1) * message.width,
              message.bytes.getRange(start, start + message.width),
            );
          }
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

      // [LABEL: Feature Extraction] Real-time QR detection on the full live frame and the
      // high-resolution fallback. This is crucial when a QR occupies a large portion of a monitor
      // and the fiber of the phone camera sees glare, scanlines, or partial tilt.
      QrDetectionResult? qrResult = QrDetectionService.detectWithCorners(processedMat, fastMode: false);
      qrResult ??= _scanQrRegion(processedMat);
      final alignmentQrCorners = qrResult?.corners;
      qrResult ??= QrDetectionService.detectWithCorners(smallMat, fastMode: true);
      qrResult ??= _scanQrRegion(mat);
      qrResult ??= QrDetectionService.detectWithCorners(mat, fastMode: true);
      final rawFrameQr = qrResult == null ? QrDetectionService.detectEntireImage(mat) : null;
      final detectedQr = qrResult?.data ?? rawFrameQr;
      final qrCorners = qrResult?.corners ??
          (detectedQr != null && detectedQr.sheetIdentifier.isNotEmpty && detectedQr.sheetIdentifier != 'UNKNOWN'
              ? const [0.20, 0.20, 0.80, 0.20, 0.80, 0.80, 0.20, 0.80]
              : null);

      if (detectedQr == null) {
        debugPrint('LIVE QR: no QR detected in full frame or explicit ROI scan');
      } else {
        debugPrint('LIVE QR: ${detectedQr.sheetIdentifier}');
      }

      // Find the printed markers in this frame, without fixed corner zones or
      // a paper-edge aspect-ratio gate that rejects foreshortened sheets.
      final candidates = SheetAlignmentService.findCandidates(processedMat);
      List<SheetPoint>? markerCorners;
      for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
        markerCorners = FiducialGeometry.selectMarkers(candidates,
            imageArea: (finalW * finalH).toDouble(),
            aspectRatio: layout.$1, diameterRatio: layout.$2,
            qrCenter: _qrCenter(alignmentQrCorners, finalW, finalH));
        if (markerCorners != null) break;
      }
      final foundPaper = markerCorners != null;
      final paperCorners = markerCorners?.expand((p) =>
          [p.x / finalW, p.y / finalH]).toList();
      Uint8List? debugBytes;
      if (message.returnDebugImage) {
        debugBytes = Uint8List.fromList(cv.imencode('.jpg', processedMat).$2);
      }

      message.replyPort.send(ScanResponse(
        foundPaper: foundPaper,
        scanSession: message.scanSession,
        corners: paperCorners,
        debugImage: debugBytes,
        detectedQr: detectedQr,
        qrCorners: qrCorners,
      ));

    } catch (e, stack) {
      debugPrint("LIVE SCAN ISOLATE ERROR: $e\n$stack");
      message.replyPort.send(ScanResponse(
        foundPaper: false,
        scanSession: message.scanSession,
      ));
    } finally {
      // [LABEL: Cleanup] Prevent FFI Memory Leaks
      pool.disposeAll();
    }
  }

  static QrDetectionResult? _scanQrRegion(cv.Mat source) {
    final pool = CvPool();
    try {
      final int w = source.width;
      final int h = source.height;
      final List<cv.Rect> regions = [
        cv.Rect((w * 0.55).toInt(), (h * 0.02).toInt(), (w * 0.40).toInt(), (h * 0.28).toInt()),
        cv.Rect((w * 0.15).toInt(), (h * 0.02).toInt(), (w * 0.70).toInt(), (h * 0.32).toInt()),
        cv.Rect(0, 0, w, h),
      ];

      for (final region in regions) {
        final crop = pool.add(source.region(region));
        final detector = pool.add(cv.QRCodeDetector.empty());
        final (text, points, _) = detector.detectAndDecode(crop);
        if (text.isNotEmpty) {
          final corners = points.isNotEmpty
              ? [
                  points[0].x.toDouble() / crop.width,
                  points[0].y.toDouble() / crop.height,
                  points[1].x.toDouble() / crop.width,
                  points[1].y.toDouble() / crop.height,
                  points[2].x.toDouble() / crop.width,
                  points[2].y.toDouble() / crop.height,
                  points[3].x.toDouble() / crop.width,
                  points[3].y.toDouble() / crop.height,
                ]
              : null;
          final normalized = corners == null ? null : <double>[
            ((region.x + points[0].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points[0].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points[1].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points[1].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points[2].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points[2].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points[3].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points[3].y.toDouble()) / h).clamp(0.0, 1.0),
          ];
          return QrDetectionResult(data: QrData.fromRaw(text), corners: normalized);
        }

        final gray = pool.add(crop.channels == 3 ? cv.cvtColor(crop, cv.COLOR_BGR2GRAY) : crop);
        final (_, binary) = cv.threshold(gray, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
        final detector2 = pool.add(cv.QRCodeDetector.empty());
        final (text2, points2, _) = detector2.detectAndDecode(binary);
        if (text2.isNotEmpty) {
          final normalized = <double>[
            ((region.x + points2[0].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points2[0].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points2[1].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points2[1].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points2[2].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points2[2].y.toDouble()) / h).clamp(0.0, 1.0),
            ((region.x + points2[3].x.toDouble()) / w).clamp(0.0, 1.0),
            ((region.y + points2[3].y.toDouble()) / h).clamp(0.0, 1.0),
          ];
          return QrDetectionResult(data: QrData.fromRaw(text2), corners: normalized);
        }
      }
    } catch (e) {
      debugPrint('LIVE QR ROI scan failed: $e');
    } finally {
      pool.disposeAll();
    }
    return null;
  }

  static SheetPoint? _qrCenter(List<double>? corners, int width, int height) {
    if (corners == null || corners.length != 8) return null;
    var x = 0.0;
    var y = 0.0;
    for (var i = 0; i < 4; i++) {
      x += corners[i * 2];
      y += corners[i * 2 + 1];
    }
    return SheetPoint(x * width / 4, y * height / 4);
  }

  static BubbleSheetTemplate _processingTemplate(
      BubbleSheetTemplate supplied, QrData? qr) {
    // Metadata resolved before capture is authoritative. A short Sheet ID's
    // legacy QR parser defaults to 50 questions and must not override it.
    if (supplied.id != 'custom' || qr == null) return supplied;
    final name = qr.templateName;
    if (name != null && name.isNotEmpty) {
      for (final template in AnswerSheetTemplateRegistry.all) {
        if (template.name == name || template.id == name) return template;
      }
    }
    if (qr.examCode.startsWith('CM50')) return Standard50QuestionsTemplate();
    if (qr.examCode.contains('PY5')) return PyImageSearch5Template();
    return supplied;
  }

  /// Internal isolated process for High-Res OMR
  static ProcessedSheet? _processOmrInternal(OmrRequest message) {
    final pool = CvPool();
    try {
      cv.Mat mat = pool.add(cv.imdecode(message.bytes, cv.IMREAD_COLOR));
      if (mat.isEmpty) {
        return null;
      }

      // Downsample oversized camera captures (e.g. 12MP/4K photos) to max 2000px width
      // to prevent native Out-Of-Memory (OOM) crashes while preserving 100% OMR accuracy.
      if (mat.width > 2000) {
        final double scale = 2000.0 / mat.width;
        final int newH = (mat.height * scale).toInt();
        mat = pool.add(cv.resize(mat, (2000, newH)));
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

      final capturedQr = QrDetectionService.detectWithCorners(mat);
      final rawImageQr = capturedQr?.data;
      if (rawImageQr != null && rawImageQr.sheetIdentifier.isNotEmpty && rawImageQr.sheetIdentifier != "UNKNOWN") {
        debugPrint("OMR: Found QR on raw unwarped image -> ${rawImageQr.sheetIdentifier}");
      }

      final activeTemplate = _processingTemplate(
          message.template, rawImageQr ?? message.expectedQr);
      // Preview and still capture can differ in field of view, rotation, and
      // timing. Resolve markers afresh in the decoded photograph.
      final capturedMarkers = SheetAlignmentService.detectMarkers(mat,
          aspectRatio: activeTemplate.fiducialAspectRatio,
          diameterRatio: activeTemplate.fiducialDiameterRatio,
          qrCenter: _qrCenter(capturedQr?.corners, mat.width, mat.height));
      if (capturedMarkers == null) {
        throw const SheetAlignmentException();
      }
      final targetWidth = activeTemplate.targetWidth;
      final outputRatio = activeTemplate.paperAspectRatio > 0.1
          ? activeTemplate.paperAspectRatio : activeTemplate.fiducialAspectRatio;
      final targetHeight = (targetWidth / outputRatio).round();
      final destination = pool.add(PerspectiveService.getDestPoints(
          targetWidth, targetHeight, 0));
      // Marker selection has already established cyclic order and axis
      // assignment. Reordering here could undo that under extreme perspective.
      final transform = pool.add(cv.getPerspectiveTransform(
          capturedMarkers, destination));
      final warped = pool.add(cv.warpPerspective(
          mat, transform, (targetWidth, targetHeight)));
      QrData? qrData = rawImageQr;

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
        if (message.expectedQr != null && message.expectedQr!.examCode != "UNKNOWN") {
          debugPrint("OMR: Could not find QR in warped image, falling back to scanner's locked QR data.");
          qrData = message.expectedQr;
        } else {
          try {
            debugPrint("OMR: QR completely failed, extracting ID dynamically via template constraints...");
            final int targetH = (mat.height * (800.0 / mat.width)).toInt();
            final smallMat = pool.add(cv.resize(mat, (800, targetH)));
            final smallQr = QrDetectionService.detectEntireImage(smallMat);
            if (smallQr != null && smallQr.examCode != "UNKNOWN") {
              qrData = smallQr;
            }
          } catch (_) {}
        }
      }

      debugPrint('OMR: Active Template -> ${activeTemplate.name}');

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

      double gridStart = activeTemplate.gridStart;
      double gridWidth = activeTemplate.gridWidth;
      int calibratedY = activeTemplate.calibratedYOffset;

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
    } on SheetAlignmentException {
      rethrow;
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
