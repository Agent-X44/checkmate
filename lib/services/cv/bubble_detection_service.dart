import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flutter/material.dart';

import '../../models/omr/bubble_result.dart';
export '../../models/omr/bubble_result.dart';

class BubbleDetectionService {
  static BubbleResult detectAtPoints(cv.Mat binary, List<Offset> points,
      {required double radiusRatio, required double threshold}) {
    final radius = (binary.width * radiusRatio).round().clamp(1, binary.width);
    final ratios = <double>[];
    for (final p in points) {
      final left =
          (p.dx * binary.width - radius).round().clamp(0, binary.width - 1);
      final top =
          (p.dy * binary.height - radius).round().clamp(0, binary.height - 1);
      final width = (radius * 2).clamp(1, binary.width - left);
      final height = (radius * 2).clamp(1, binary.height - top);
      final cell = binary.region(cv.Rect(left, top, width, height));
      ratios.add(cv.countNonZero(cell) / (width * height));
    }
    final answers = [
      for (var i = 0; i < ratios.length; i++)
        if (ratios[i] > threshold) String.fromCharCode(65 + i)
    ];
    final sorted = List<double>.of(ratios)..sort((a, b) => b.compareTo(a));
    return BubbleResult(
        answer: answers.length == 1 ? answers.single : null,
        confidence: sorted.length < 2 ? 0 : (sorted[0] - sorted[1]).clamp(0, 1),
        isFilled: answers.isNotEmpty,
        multipleAnswers: answers,
        isAmbiguous: answers.length > 1);
  }

  /// Pixel (x, y, width, height) of each choice's sampled zone in a row of
  /// size [w] x [h]. Shared by grading and the developer overlay.
  static List<(int, int, int, int)> choiceZones(int w, int h, int choicesCount,
      {required double gridStart,
      required double gridWidthRatio,
      required double zoneWidthRatio,
      required double zoneHeightRatio}) {
    final double gridStartX = w * gridStart;
    final double cellWidth = w * gridWidthRatio / choicesCount;
    return [
      for (int i = 0; i < choicesCount; i++)
        () {
          final double xStart = gridStartX +
              (i * cellWidth) +
              (cellWidth * (1 - zoneWidthRatio) / 2);
          final double yStart = h * (1 - zoneHeightRatio) / 2;
          // A wide grid may place an outer zone partly past the region edge;
          // sample only the part inside it.
          final x = xStart.toInt().clamp(0, w - 1);
          var width = (cellWidth * zoneWidthRatio).toInt();
          if (xStart < 0) width += xStart.toInt();
          return (
            x,
            yStart.toInt().clamp(0, h - 1),
            width.clamp(1, w - x),
            (h * zoneHeightRatio).toInt().clamp(1, h - yStart.toInt()),
          );
        }()
    ];
  }

  /// Processes a single question row using HIGH-PRECISION GRID mapping.
  static BubbleResult detectFilledBubble(
    cv.Mat rowMat,
    int choicesCount, {
    bool isBinary = false,
    double gridStart = 0.15,
    double gridWidthRatio = 0.82,
    double zoneWidthRatio = 0.45,
    double zoneHeightRatio = 0.60,
    List<double>? customXOffsets,
    double threshold = 0.18,
  }) {
    cv.Mat binary;
    if (isBinary) {
      binary = rowMat.clone();
    } else {
      cv.Mat gray = rowMat.channels == 3
          ? cv.cvtColor(rowMat, cv.COLOR_BGR2GRAY)
          : rowMat.clone();
      final (_, otsu) =
          cv.threshold(gray, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU);
      binary = otsu;
    }

    final int w = binary.width;
    final int h = binary.height;

    final List<double> fillRatios = [];

    // 2. MEASURE DENSITY
    if (customXOffsets != null && customXOffsets.isNotEmpty) {
      for (double relX in customXOffsets) {
        final rect = cv.Rect(
          (relX * w - (w * 0.05)).toInt().clamp(0, w - 1),
          (h * 0.15).toInt().clamp(0, h - 1),
          (w * 0.10).toInt().clamp(1, w - (relX * w - (w * 0.05)).toInt()),
          (h * 0.70).toInt().clamp(1, h - (h * 0.15).toInt()),
        );
        final cellMat = binary.region(rect);
        fillRatios.add(cv.countNonZero(cellMat) / (rect.width * rect.height));
      }
    } else {
      for (final (x, y, zw, zh) in choiceZones(w, h, choicesCount,
          gridStart: gridStart,
          gridWidthRatio: gridWidthRatio,
          zoneWidthRatio: zoneWidthRatio,
          zoneHeightRatio: zoneHeightRatio)) {
        final cellMat = binary.region(cv.Rect(x, y, zw, zh));

        // Binary ink is white after inverse thresholding. Count only actual
        // ink pixels: the external contour area of an unfilled printed ring
        // includes its empty center and can falsely grade it as marked.
        fillRatios.add(cv.countNonZero(cellMat) / (zw * zh));
      }
    }

    // 3. IDENTIFY ALL FILLED BUBBLES
    final List<int> filledIndices = [];
    for (int i = 0; i < fillRatios.length; i++) {
      if (fillRatios[i] > threshold) {
        filledIndices.add(i);
      }
    }

    // 4. MAP TO LETTERS
    final List<String> answers =
        filledIndices.map((i) => String.fromCharCode(65 + i)).toList();

    final sortedRatios = List<double>.from(fillRatios)
      ..sort((a, b) => b.compareTo(a));
    double maxFill = sortedRatios.isNotEmpty ? sortedRatios[0] : 0.0;
    double secondMaxFill = sortedRatios.length > 1 ? sortedRatios[1] : 0.0;
    double confidence = (maxFill - secondMaxFill).clamp(0.0, 1.0);

    return BubbleResult(
      answer: answers.length == 1 ? answers.first : null,
      confidence: confidence,
      isFilled: answers.isNotEmpty,
      multipleAnswers: answers,
      isAmbiguous: answers.length > 1,
    );
  }
}
