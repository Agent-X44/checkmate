import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/qr_data.dart';
import '../models/omr/templates/py_image_search_5.dart';
import '../models/omr/templates/standard_50_questions.dart';
import 'cv/sheet_alignment_service.dart';
import 'cv/fiducial_geometry.dart';
import 'cv/threshold_service.dart';
import 'cv/template_service.dart';
import 'cv/bubble_detection_service.dart';
import 'cv/qr_detection_service.dart';
import 'cv/camera_frame_service.dart';
import 'cv/live_scan_policy.dart';
import '../config/app_build.dart';
import '../models/omr/template_calibration.dart';

// [LABEL: Request Models]

/// Data structure for passing camera frame data and tuning parameters to the Isolate.
class ScanRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int bytesPerPixel;
  final SendPort replyPort;
  final int scanSession;
  final int capturedAtMicros;

  final double cannyThreshold1;
  final double cannyThreshold2;
  final double blurSigma;
  final double sensitivity;
  final int rotationIndex;
  final bool returnDebugImage;
  final bool detectQr;

  ScanRequest({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
    required this.replyPort,
    this.scanSession = 0,
    this.capturedAtMicros = 0,
    this.cannyThreshold1 = 50.0,
    this.cannyThreshold2 = 150.0,
    this.blurSigma = 0.0,
    this.sensitivity = 0.02,
    this.rotationIndex = 1,
    this.returnDebugImage = false,
    this.detectQr = true,
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
  final TemplateCalibration? calibration;
  final List<TemplateCalibration> calibrationProfiles;
  final bool developerSandbox;

  OmrRequest({
    required this.bytes,
    required this.corners,
    required this.template,
    this.replyPort,
    this.stripHeightMultiplier = 1.2,
    this.customSetRegion,
    this.customSetBubbles,
    this.expectedQr,
    this.calibration,
    this.calibrationProfiles = const [],
    this.developerSandbox = false,
  });
}

/// No deterministic item grading may run on an unverified alignment.
class SheetAlignmentException implements Exception {
  const SheetAlignmentException();

  @override
  String toString() => 'Could not align the answer sheet. Keep all four corner '
      'circles fully visible, hold steady for focus, and retake.';
}

class SheetIdentityException implements Exception {
  final bool unreadable;

  const SheetIdentityException({this.unreadable = false});

  @override
  String toString() => unreadable
      ? 'Could not read the QR code in this photo. Keep it visible, tap to '
          'focus, and retake.'
      : 'The captured sheet differs from the selected student. '
          'Scan its QR code again before capturing.';
}

/// Response containing detection results and optional debug imagery.
class ScanResponse {
  final bool foundPaper;
  final int scanSession;
  final int capturedAtMicros;
  final List<double>? corners; // Normalized coordinates [x1, y1, ...]
  final Uint8List? debugImage;
  final QrData? detectedQr;
  final List<double>?
      qrCorners; // Normalized QR corners [x0, y0, x1, y1, x2, y2, x3, y3]

  ScanResponse({
    required this.foundPaper,
    this.scanSession = 0,
    this.capturedAtMicros = 0,
    this.corners,
    this.debugImage,
    this.detectedQr,
    this.qrCorners,
  });
}

class _LiveTrackingState {
  int? session;
  (int, int, int)? frameShape;
  List<SheetPoint>? corners;
  (double, double)? layout;
  int lastQrAt = 0;
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

    final tracking = _LiveTrackingState();
    receivePort.listen((message) {
      if (message is ScanRequest) {
        _handleLiveScan(message, tracking);
      } else if (message is OmrRequest) {
        debugPrint("OMR ISOLATE: Received high-res request (legacy path)");
        final result = _processOmrInternal(message);
        message.replyPort?.send(result);
      }
    });
  }

  static void _handleLiveScan(
      ScanRequest message, _LiveTrackingState tracking) {
    final pool = CvPool();
    try {
      // 1. [LABEL: Data Ingestion] Mat Creation & Row Stride Handling
      final luminance = CameraFrameService.luminance(
        bytes: message.bytes,
        width: message.width,
        height: message.height,
        bytesPerRow: message.bytesPerRow,
        bytesPerPixel: message.bytesPerPixel,
      );
      final mat = pool.add(cv.Mat.fromList(
          message.height, message.width, cv.MatType.CV_8UC1, luminance));

      // Bound preview work by the long edge and never upscale camera frames.
      // Capture still uses its original detail and independent alignment.
      final scale = math.min(
          1.0,
          LiveScanPolicy.previewMaxDimension /
              math.max(message.width, message.height));
      final smallMat = scale < 1
          ? pool.add(cv.resize(mat, (
              (message.width * scale).round(),
              (message.height * scale).round()
            )))
          : mat;
      var processedMat = smallMat;
      if (message.rotationIndex == 1) {
        processedMat = pool.add(cv.rotate(smallMat, cv.ROTATE_90_CLOCKWISE));
      } else if (message.rotationIndex == 2) {
        processedMat = pool.add(cv.rotate(smallMat, cv.ROTATE_180));
      } else if (message.rotationIndex == 3) {
        processedMat =
            pool.add(cv.rotate(smallMat, cv.ROTATE_90_COUNTERCLOCKWISE));
      }
      final finalW = processedMat.width;
      final finalH = processedMat.height;
      final shape = (message.width, message.height, message.rotationIndex);
      if (tracking.session != message.scanSession ||
          tracking.frameShape != shape) {
        tracking.session = message.scanSession;
        tracking.frameShape = shape;
        tracking.corners = null;
        tracking.layout = null;
        tracking.lastQrAt = 0;
      }
      List<SheetPoint>? markerCorners;
      final previous = tracking.corners;
      final layout = tracking.layout;
      if (previous != null && layout != null) {
        final shortEdge = math.min(previous[0].distanceTo(previous[1]),
            previous[1].distanceTo(previous[2]));
        final widestEdge = math.max(previous[0].distanceTo(previous[1]),
            previous[2].distanceTo(previous[3]));
        final radius = math
            .max(shortEdge * 0.22, widestEdge * layout.$2 * 1.3)
            .clamp(24.0, 128.0);
        final nearby = SheetAlignmentService.findNearbyCandidates(
            processedMat, previous, radius);
        markerCorners = FiducialGeometry.trackMarkers(previous, nearby,
            searchRadius: radius,
            aspectRatio: layout.$1,
            diameterRatio: layout.$2);
      }
      List<FiducialCandidate>? candidates;
      void acquire({SheetPoint? qrCenter}) {
        candidates ??= SheetAlignmentService.findCandidates(processedMat,
            thresholdWindows: const [51]);
        for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
          markerCorners = FiducialGeometry.selectMarkers(candidates!,
              imageArea: (finalW * finalH).toDouble(),
              aspectRatio: layout.$1,
              diameterRatio: layout.$2,
              qrCenter: qrCenter);
          if (markerCorners != null) {
            tracking.layout = layout;
            break;
          }
        }
      }

      if (markerCorners == null) acquire();
      QrData? detectedQr;
      List<double>? qrCorners;
      // ML Kit identifies sheets independently. Native QR work is needed only
      // to disambiguate acquisition or for unsupported platform buffers, and
      // must not compete with the fast marker path on every frame.
      final now = DateTime.now().microsecondsSinceEpoch;
      if ((markerCorners == null || message.detectQr) &&
          now - tracking.lastQrAt >= LiveScanPolicy.qrInterval.inMicroseconds) {
        tracking.lastQrAt = now;
        try {
          final detector = pool.add(cv.QRCodeDetector.empty());
          final (located, points) = detector.detect(processedMat);
          if (located && points.length >= 4) {
            qrCorners = [
              for (var i = 0; i < 4; i++) ...[
                points[i].x / finalW,
                points[i].y / finalH
              ]
            ];
            if (message.detectQr) {
              final (text, _, _) =
                  detector.decode(processedMat, points: points);
              if (text.isNotEmpty) detectedQr = QrData.fromRaw(text);
            }
            if (markerCorners == null) {
              acquire(qrCenter: _qrCenter(qrCorners, finalW, finalH));
            }
          }
        } catch (error) {
          debugPrint('Live QR location unavailable: $error');
        }
      }
      tracking.corners = markerCorners;
      if (markerCorners == null) tracking.layout = null;
      final foundPaper = markerCorners != null;
      final paperCorners =
          markerCorners?.expand((p) => [p.x / finalW, p.y / finalH]).toList();
      Uint8List? debugBytes;
      if (message.returnDebugImage) {
        debugBytes = Uint8List.fromList(cv.imencode('.jpg', processedMat).$2);
      }

      message.replyPort.send(ScanResponse(
        foundPaper: foundPaper,
        scanSession: message.scanSession,
        capturedAtMicros: message.capturedAtMicros,
        corners: paperCorners,
        debugImage: debugBytes,
        detectedQr: detectedQr,
        qrCorners: qrCorners,
      ));
    } catch (e, stack) {
      tracking.corners = null;
      tracking.layout = null;
      debugPrint("LIVE SCAN ISOLATE ERROR: $e\n$stack");
      message.replyPort.send(ScanResponse(
        foundPaper: false,
        scanSession: message.scanSession,
        capturedAtMicros: message.capturedAtMicros,
      ));
    } finally {
      // [LABEL: Cleanup] Prevent FFI Memory Leaks
      pool.disposeAll();
    }
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

      // Bound both axes while preserving far-marker detail for the retry pass.
      final longestSide = math.max(mat.width, mat.height);
      if (longestSide > 3000) {
        final scale = 3000.0 / longestSide;
        mat = pool.add(cv.resize(
            mat, ((mat.width * scale).round(), (mat.height * scale).round())));
      }

      final expectedId = message.expectedQr?.sheetIdentifier;
      final sandbox = AppBuild.developerTools && message.developerSandbox;
      final capturedQr = sandbox
          ? null
          : expectedId == null
              ? QrDetectionService.detectWithCorners(mat)
              : QrDetectionService.detectMatchingSheet(mat, expectedId);
      final rawImageQr = capturedQr?.data;
      _verifyCapturedIdentity(rawImageQr, expectedId);
      if (rawImageQr != null &&
          rawImageQr.sheetIdentifier.isNotEmpty &&
          rawImageQr.sheetIdentifier != "UNKNOWN") {
        debugPrint(
            "OMR: Found QR on raw unwarped image -> ${rawImageQr.sheetIdentifier}");
      }

      final preferredTemplate = _processingTemplate(
          message.template, rawImageQr ?? message.expectedQr);
      // Preview and still capture can differ in field of view, rotation, and
      // timing. Resolve markers afresh in the decoded photograph.
      final markerMatch = SheetAlignmentService.detectTemplateMarkers(mat,
          preferred: preferredTemplate,
          developerSandbox: sandbox,
          qrCenter: _qrCenter(capturedQr?.corners, mat.width, mat.height));
      if (markerMatch == null) {
        throw const SheetAlignmentException();
      }
      final activeTemplate = markerMatch.template;
      final capturedMarkers = markerMatch.corners;
      TemplateCalibration? calibration;
      if (AppBuild.developerTools) {
        for (final profile in message.calibrationProfiles) {
          if (profile.baseTemplateId == activeTemplate.id) {
            calibration = profile;
          }
        }
        if (message.calibration?.baseTemplateId == activeTemplate.id) {
          calibration = message.calibration;
        }
      }
      final targetWidth = activeTemplate.targetWidth;
      final outputRatio = activeTemplate.paperAspectRatio > 0.1
          ? activeTemplate.paperAspectRatio
          : activeTemplate.fiducialAspectRatio;
      final targetHeight = (targetWidth / outputRatio).round();
      final destination = pool.add(cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(targetWidth.toDouble(), 0),
        cv.Point2f(targetWidth.toDouble(), targetHeight.toDouble()),
        cv.Point2f(0, targetHeight.toDouble()),
      ]));
      // Marker selection has already established cyclic order and axis
      // assignment. Reordering here could undo that under extreme perspective.
      final sourcePoints = pool.add(cv.VecPoint2f.fromList(
          capturedMarkers.map((p) => cv.Point2f(p.x, p.y)).toList()));
      final transform =
          pool.add(cv.getPerspectiveTransform2f(sourcePoints, destination));
      final warped = pool
          .add(cv.warpPerspective(mat, transform, (targetWidth, targetHeight)));
      QrData? qrData = rawImageQr;

      if (!sandbox) {
        if (qrData == null || qrData.examCode == "UNKNOWN") {
          final warpedQr = QrDetectionService.detectEntireImage(warped);
          if (warpedQr != null && warpedQr.examCode != "UNKNOWN") {
            qrData = warpedQr;
          }
        }

        final qrRegion = AppBuild.developerTools
            ? calibration?.qrRegion ?? activeTemplate.qrRegion
            : activeTemplate.qrRegion;
        if ((qrData == null || qrData.examCode == "UNKNOWN") &&
            qrRegion != null) {
          final regionalQr = QrDetectionService.detectQr(warped, qrRegion);
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
            debugPrint(
                "OMR: Retrying captured QR at an alternate image scale...");
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

      // A preview lock can be stale after moving the camera to another sheet.
      // Only a QR decoded from this photograph may establish its identity.
      if (!sandbox) {
        _verifyCapturedIdentity(qrData, expectedId, requireDecoded: true);
      }

      return _readWarped(warped, activeTemplate, qrData,
          stripHeight: message.stripHeightMultiplier,
          customSetRegion: message.customSetRegion,
          customSetBubbles: message.customSetBubbles,
          calibration: calibration);
    } on SheetAlignmentException {
      rethrow;
    } on SheetIdentityException {
      rethrow;
    } catch (e, stack) {
      debugPrint("OMR PROCESSOR ERROR: $e\n$stack");
      return null;
    } finally {
      pool.disposeAll();
    }
  }

  /// Developer-only local inspection: no identity lookup or grade sync occurs.
  static Future<ProcessedSheet> previewCalibration(ProcessedSheet sheet,
      BubbleSheetTemplate template, TemplateCalibration config) async {
    if (!AppBuild.developerTools) {
      throw StateError('Developer edition required');
    }
    return Isolate.run(() {
      final image = cv.imdecode(sheet.warpedImage, cv.IMREAD_COLOR);
      if (image.isEmpty) {
        throw const FormatException('Could not read this image');
      }
      return _readWarped(image, template, sheet.qrData, calibration: config);
    });
  }

  static ProcessedSheet _readWarped(
      cv.Mat warped, BubbleSheetTemplate activeTemplate, QrData? qrData,
      {double stripHeight = 1.2,
      Rect? customSetRegion,
      List<Offset>? customSetBubbles,
      TemplateCalibration? calibration}) {
    final pool = CvPool();
    final thresholded = pool.add(ThresholdService.applyOtsuThreshold(warped));

    String? detectedSet;
    final setRegion =
        calibration?.setRegion ?? customSetRegion ?? activeTemplate.setRegion;
    final setBubbles = calibration?.setBubbles ??
        customSetBubbles ??
        activeTemplate.setBubbles;

    if (setBubbles != null && setBubbles.isNotEmpty) {
      detectedSet = _detectSetFromBubbles(thresholded, setBubbles);
    } else if (setRegion != null) {
      detectedSet = _detectSetFromRegion(thresholded, setRegion);
    }

    final List<BubbleResult> results = [];
    final List<Uint8List> questionImages = [];

    double gridStart = calibration?.gridStart ?? activeTemplate.gridStart;
    double gridWidth = calibration?.gridWidth ?? activeTemplate.gridWidth;
    int calibratedY = calibration?.yOffset ?? activeTemplate.calibratedYOffset;

    final List<Rect> activeRegions =
        calibration?.answerRegions ?? activeTemplate.answerRegions;
    final int questionsPerRegion =
        (activeTemplate.totalQuestions / activeRegions.length).ceil();

    for (int i = 0; i < activeRegions.length; i++) {
      final region = activeRegions[i];
      final regionMat = pool.add(TemplateService.extractRegion(
          thresholded, region,
          xOffset: calibration?.xOffset ?? 0));
      final questionsInThisRegion = (i == activeRegions.length - 1)
          ? activeTemplate.totalQuestions - (questionsPerRegion * i)
          : questionsPerRegion;

      final questionMats = TemplateService.splitQuestions(
        regionMat,
        questionsInThisRegion,
        yOffset: calibratedY,
        heightMultiplier: calibration?.stripHeight ?? stripHeight,
        ySpace: calibration?.rowSpacing ?? 0,
      );

      for (final m in questionMats) {
        pool.add(m);
        final result = BubbleDetectionService.detectFilledBubble(
          m,
          activeTemplate.choicesPerQuestion,
          isBinary: true,
          gridStart: gridStart,
          gridWidthRatio: gridWidth,
          threshold: calibration?.fillThreshold ?? .18,
          zoneWidthRatio: calibration?.zoneWidth ?? .45,
          zoneHeightRatio: calibration?.zoneHeight ?? .60,
        );
        results.add(result);
        questionImages.add(Uint8List.fromList(cv.imencode(".jpg", m).$2));
      }
    }

    final bubbles = calibration?.answerBubbles;
    if (bubbles != null && bubbles.isNotEmpty) {
      var offset = 0;
      results.clear();
      questionImages.clear();
      for (var i = 0; i < activeTemplate.totalQuestions; i++) {
        final choices =
            activeTemplate.tfCount > 0 && i >= activeTemplate.mcqCount
                ? 2
                : activeTemplate.choicesPerQuestion;
        if (offset + choices > bubbles.length) {
          throw const FormatException(
              'Add every answer bubble, in question and choice order');
        }
        results.add(BubbleDetectionService.detectAtPoints(
            thresholded, bubbles.sublist(offset, offset + choices),
            radiusRatio: calibration!.bubbleRadius,
            threshold: calibration.fillThreshold));
        offset += choices;
      }
      if (offset != bubbles.length) {
        throw const FormatException('Remove extra answer bubbles');
      }
    }
    final warpedBytes = Uint8List.fromList(cv.imencode(".jpg", warped).$2);
    final thresholdBytes =
        Uint8List.fromList(cv.imencode(".jpg", thresholded).$2);
    final legacyAnswerArea =
        pool.add(TemplateService.extractRegion(warped, activeRegions.first));
    final answerAreaBytes =
        Uint8List.fromList(cv.imencode(".jpg", legacyAnswerArea).$2);

    return ProcessedSheet(
      warpedImage: warpedBytes,
      thresholdImage: thresholdBytes,
      answerRegion: answerAreaBytes,
      questionImages: questionImages,
      results: results,
      qrData: qrData,
      detectedSet: detectedSet,
      templateName: calibration?.name ?? activeTemplate.name,
      templateId: activeTemplate.id,
      questionCapacity: activeTemplate.totalQuestions,
    );
  }

  static void _verifyCapturedIdentity(QrData? captured, String? expectedId,
      {bool requireDecoded = false}) {
    final decoded = captured != null &&
        captured.sheetIdentifier.isNotEmpty &&
        captured.sheetIdentifier != 'UNKNOWN';
    if (requireDecoded && !decoded) {
      throw const SheetIdentityException(unreadable: true);
    }
    if (captured != null &&
        captured.sheetIdentifier.isNotEmpty &&
        captured.sheetIdentifier != 'UNKNOWN' &&
        expectedId != null &&
        expectedId.isNotEmpty &&
        expectedId != 'UNKNOWN' &&
        captured.sheetIdentifier != expectedId) {
      throw const SheetIdentityException();
    }
  }

  static String? _detectSetFromBubbles(
      cv.Mat thresholded, List<Offset> setBubbles) {
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
      final setMat =
          pool.add(TemplateService.extractRegion(thresholded, setRegion));
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
