import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/omr/qr_data.dart';
import 'image_preprocessing_service.dart';
import 'perspective_service.dart';

class QrDetectionResult {
  final QrData data;
  final List<double>? corners;

  QrDetectionResult({required this.data, this.corners});
}

class QrPool {
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

class QrDetectionService {
  static QrData? detectQr(cv.Mat warped, ui.Rect region) {
    return detectWithCorners(warped, region: region)?.data;
  }

  static QrDetectionResult? detectWithCorners(cv.Mat input, {ui.Rect? region, bool fastMode = false}) {
    if (input.isEmpty) return null;

    final List<ui.Rect> regionStack = [];
    if (region != null && region != const ui.Rect.fromLTRB(0.0, 0.0, 1.0, 1.0)) {
      regionStack.add(region);
    }
    regionStack.addAll([
      const ui.Rect.fromLTRB(0.0, 0.0, 1.0, 1.0),
      const ui.Rect.fromLTRB(0.10, 0.10, 0.90, 0.90),
      const ui.Rect.fromLTRB(0.00, 0.00, 0.75, 0.75),
      const ui.Rect.fromLTRB(0.25, 0.00, 1.00, 0.75),
      const ui.Rect.fromLTRB(0.00, 0.25, 0.75, 1.00),
    ]);

    try {
      // 1. Primary Sweep: Default orientation (0 deg)
      for (final regionCandidate in regionStack) {
        final result = _tryRegionWithRotation(
          inputMat: input,
          testRegion: regionCandidate,
          angleDegree: 0,
          fastMode: fastMode,
        );
        if (result != null) return result;
      }

      // 2. Fallback Sweep: 90 deg rotation
      final cv.Mat rot90 = cv.rotate(input, cv.ROTATE_90_CLOCKWISE);
      for (final regionCandidate in regionStack) {
        final result = _tryRegionWithRotation(
          inputMat: rot90,
          testRegion: regionCandidate,
          rotationCode: cv.ROTATE_90_CLOCKWISE,
          angleDegree: 90,
          fastMode: fastMode,
        );
        if (result != null) {
          rot90.dispose();
          return result;
        }
      }
      rot90.dispose();

      // 3. Fallback Sweep: 270 deg rotation
      final cv.Mat rot270 = cv.rotate(input, cv.ROTATE_90_COUNTERCLOCKWISE);
      for (final regionCandidate in regionStack) {
        final result = _tryRegionWithRotation(
          inputMat: rot270,
          testRegion: regionCandidate,
          rotationCode: cv.ROTATE_90_COUNTERCLOCKWISE,
          angleDegree: 270,
          fastMode: fastMode,
        );
        if (result != null) {
          rot270.dispose();
          return result;
        }
      }
      rot270.dispose();

      // 4. Fallback Sweep: 180 deg rotation
      final cv.Mat rot180 = cv.rotate(input, cv.ROTATE_180);
      for (final regionCandidate in regionStack) {
        final result = _tryRegionWithRotation(
          inputMat: rot180,
          testRegion: regionCandidate,
          rotationCode: cv.ROTATE_180,
          angleDegree: 180,
          fastMode: fastMode,
        );
        if (result != null) {
          rot180.dispose();
          return result;
        }
      }
      rot180.dispose();
    } catch (e) {
      debugPrint("QR Detection Error: $e");
    }
    return null;
  }

  static QrData? searchBroad(cv.Mat warped) {
    return detectQr(warped, const ui.Rect.fromLTRB(0.4, 0.0, 1.0, 0.4));
  }

  static QrData? detectEntireImage(cv.Mat image) {
    return detectQr(image, const ui.Rect.fromLTRB(0.0, 0.0, 1.0, 1.0));
  }
}

QrDetectionResult? _tryRegionWithRotation({
  required cv.Mat inputMat,
  required ui.Rect testRegion,
  int? rotationCode,
  int angleDegree = 0,
  bool fastMode = false,
}) {
  final pool = QrPool();
  try {
    cv.Mat searchBaseMat = inputMat;
    if (rotationCode != null) {
      searchBaseMat = pool.add(cv.rotate(inputMat, rotationCode));
    }

    final offsetX = (testRegion.left * searchBaseMat.width).toInt().clamp(0, searchBaseMat.width - 1);
    final offsetY = (testRegion.top * searchBaseMat.height).toInt().clamp(0, searchBaseMat.height - 1);
    final int w = (testRegion.width * searchBaseMat.width).toInt().clamp(1, searchBaseMat.width - offsetX);
    final int h = (testRegion.height * searchBaseMat.height).toInt().clamp(1, searchBaseMat.height - offsetY);
    final searchMat = pool.add(searchBaseMat.region(cv.Rect(offsetX, offsetY, w, h)));

    return _attemptDecode(inputMat, searchMat, offsetX, offsetY, angleDegree, fastMode: fastMode);
  } catch (_) {
    return null;
  } finally {
    pool.disposeAll();
  }
}

QrDetectionResult? _attemptDecode(
  cv.Mat fullInput,
  cv.Mat m,
  int offsetX,
  int offsetY,
  int rotation, {
  bool fastMode = false,
}) {
  final pool = QrPool();
  try {
    final gray = pool.add(m.channels == 3 ? cv.cvtColor(m, cv.COLOR_BGR2GRAY) : m);

    // Strategy 1: Direct Grayscale Search
    final detector1 = pool.add(cv.QRCodeDetector.empty());
    final (text1, points1, _) = detector1.detectAndDecode(gray);
    if (text1.isNotEmpty) {
      final corners = _extractNormalizedCorners(points1, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
      return QrDetectionResult(data: QrData.fromRaw(text1), corners: corners);
    }

    // Strategy 2: 3-Level Concentric Contour Hierarchy Search (QR Finder Pattern Locator)
    try {
      final adaptiveForTree = pool.add(cv.adaptiveThreshold(
          gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, 21, 5));
      final (contoursTree, hierarchy) = cv.findContours(adaptiveForTree, cv.RETR_TREE, cv.CHAIN_APPROX_SIMPLE);
      pool.add(contoursTree);
      pool.add(hierarchy);

      final List<cv.Point> finderCenters = [];

      for (int i = 0; i < contoursTree.length; i++) {
        final cv.Vec4i h1 = hierarchy[i];
        final int child1 = h1.val3; // First child index
        if (child1 >= 0 && child1 < contoursTree.length) {
          final cv.Vec4i h2 = hierarchy[child1];
          final int child2 = h2.val3; // Second child index
          if (child2 >= 0 && child2 < contoursTree.length) {
            final area = cv.contourArea(contoursTree[i]);
            if (area >= 30 && area <= (gray.width * gray.height * 0.6)) {
              final rect = cv.boundingRect(contoursTree[i]);
              finderCenters.add(cv.Point(rect.x + rect.width ~/ 2, rect.y + rect.height ~/ 2));
            }
          }
        }
      }

      if (finderCenters.length >= 2) {
        int minX = gray.width, minY = gray.height, maxX = 0, maxY = 0;
        for (final p in finderCenters) {
          if (p.x < minX) minX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.x > maxX) maxX = p.x;
          if (p.y > maxY) maxY = p.y;
        }

        final int padX = ((maxX - minX) * 0.45).toInt().clamp(20, 250);
        final int padY = ((maxY - minY) * 0.45).toInt().clamp(20, 250);

        final cropX = (minX - padX).clamp(0, gray.width - 1);
        final cropY = (minY - padY).clamp(0, gray.height - 1);
        final cropW = (maxX + padX - cropX).clamp(1, gray.width - cropX);
        final cropH = (maxY + padY - cropY).clamp(1, gray.height - cropY);

        final qrCrop = pool.add(gray.region(cv.Rect(cropX, cropY, cropW, cropH)));
        final detectorFinder = pool.add(cv.QRCodeDetector.empty());
        final (textFinder, pointsFinder, _) = detectorFinder.detectAndDecode(qrCrop);

        if (textFinder.isNotEmpty) {
          final corners = _extractNormalizedCorners(pointsFinder, offsetX + cropX, offsetY + cropY, fullInput.width, fullInput.height, rotation);
          return QrDetectionResult(data: QrData.fromRaw(textFinder), corners: corners);
        }
      }
    } catch (_) {}

    // Strategy 3: Median Blur (Scanline / Moire filter for LCD screens)
    final median = pool.add(cv.medianBlur(gray, 3));
    final detectorMed = pool.add(cv.QRCodeDetector.empty());
    final (textMed, pointsMed, _) = detectorMed.detectAndDecode(median);
    if (textMed.isNotEmpty) {
      final corners = _extractNormalizedCorners(pointsMed, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
      return QrDetectionResult(data: QrData.fromRaw(textMed), corners: corners);
    }

    // Strategy 4: Adaptive Gaussian Thresholding
    final adaptive = pool.add(cv.adaptiveThreshold(
        gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, 31, 10));
    final detector2 = pool.add(cv.QRCodeDetector.empty());
    final (text2, points2, _) = detector2.detectAndDecode(adaptive);
    if (text2.isNotEmpty) {
      final corners = _extractNormalizedCorners(points2, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
      return QrDetectionResult(data: QrData.fromRaw(text2), corners: corners);
    }

    // Strategy 5: CLAHE + Otsu's Thresholding (Screen Glare & uneven contrast)
    final clahe = pool.add(cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8)));
    final claheGray = pool.add(clahe.apply(gray));
    final (_, otsuBinary) = cv.threshold(claheGray, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
    pool.add(otsuBinary);

    final detectorOtsu = pool.add(cv.QRCodeDetector.empty());
    final (textOtsu, pointsOtsu, _) = detectorOtsu.detectAndDecode(otsuBinary);
    if (textOtsu.isNotEmpty) {
      final corners = _extractNormalizedCorners(pointsOtsu, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
      return QrDetectionResult(data: QrData.fromRaw(textOtsu), corners: corners);
    }

    if (!fastMode) {
      // Strategy 6: Inverted Thresholding
      final (_, inverted) = cv.threshold(gray, 127, 255, cv.THRESH_BINARY_INV);
      pool.add(inverted);
      final detector3 = pool.add(cv.QRCodeDetector.empty());
      final (text3, points3, _) = detector3.detectAndDecode(inverted);
      if (text3.isNotEmpty) {
        final corners = _extractNormalizedCorners(points3, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
        return QrDetectionResult(data: QrData.fromRaw(text3), corners: corners);
      }

      // Strategy 7: Equalized Histogram
      final equalized = pool.add(cv.equalizeHist(gray));
      final detector4 = pool.add(cv.QRCodeDetector.empty());
      final (text4, points4, _) = detector4.detectAndDecode(equalized);
      if (text4.isNotEmpty) {
        final corners = _extractNormalizedCorners(points4, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
        return QrDetectionResult(data: QrData.fromRaw(text4), corners: corners);
      }

      // Strategy 8: Perspective Quadrilateral Warping (3D Tilted QR Flattener)
      final processed = pool.add(ImagePreprocessingService.prepareForQrSearch(gray));
      final (contours, _) = cv.findContours(processed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area < 300) continue;

        final perimeter = cv.arcLength(contours[i], true);
        final approx = pool.add(cv.approxPolyDP(contours[i], 0.02 * perimeter, true));

        if (approx.length == 4) {
          try {
            final ordered = pool.add(PerspectiveService.orderPoints(approx));
            final destExact = pool.add(PerspectiveService.getDestPoints(300, 300, 0.0));
            final mWarp = pool.add(cv.getPerspectiveTransform(ordered, destExact));
            final warpedQr = pool.add(cv.warpPerspective(gray, mWarp, (300, 300)));

            final detector5 = pool.add(cv.QRCodeDetector.empty());
            final (text5, points5, _) = detector5.detectAndDecode(warpedQr);

            if (text5.isNotEmpty) {
              final corners = _extractNormalizedCorners(ordered, offsetX, offsetY, fullInput.width, fullInput.height, rotation);
              return QrDetectionResult(data: QrData.fromRaw(text5), corners: corners);
            }
          } catch (_) {}
        }
      }
    }
  } catch (_) {} finally {
    pool.disposeAll();
  }
  return null;
}

List<double>? _extractNormalizedCorners(
    dynamic pts, int offsetX, int offsetY, int fullW, int fullH, [int rotation = 0]) {
  try {
    if (fullW <= 0 || fullH <= 0) return null;

    final List<cv.Point> pointList = [];
    if (pts is cv.VecPoint) {
      if (pts.length < 4) return null;
      pointList.addAll(pts.toList());
    } else if (pts is List<cv.Point>) {
      if (pts.length < 4) return null;
      pointList.addAll(pts);
    } else {
      return null;
    }

    final res = <double>[];
    for (int i = 0; i < 4; i++) {
      double px = (pointList[i].x + offsetX).toDouble();
      double py = (pointList[i].y + offsetY).toDouble();

      if (rotation == 90) {
        final double origX = py;
        final double origY = fullH - px;
        px = origX;
        py = origY;
      } else if (rotation == 270) {
        final double origX = fullW - py;
        final double origY = px;
        px = origX;
        py = origY;
      } else if (rotation == 180) {
        px = fullW - px;
        py = fullH - py;
      }

      res.add((px / fullW).clamp(0.0, 1.0));
      res.add((py / fullH).clamp(0.0, 1.0));
    }
    return res;
  } catch (_) {
    return null;
  }
}
