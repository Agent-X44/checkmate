import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../models/omr/bubble_result.dart';
export '../../models/omr/bubble_result.dart';

class BubbleDetectionService {
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
      final double gridStartX = w * gridStart;
      final double gridWidth = w * gridWidthRatio;
      final double cellWidth = gridWidth / choicesCount;

      for (int i = 0; i < choicesCount; i++) {
        final double xStart = gridStartX + (i * cellWidth);
        final rect = cv.Rect(
          (xStart + (cellWidth * (1 - zoneWidthRatio) / 2))
              .toInt()
              .clamp(0, w - 1),
          (h * (1 - zoneHeightRatio) / 2).toInt().clamp(0, h - 1),
          (cellWidth * zoneWidthRatio).toInt().clamp(
              1, w - (xStart + (cellWidth * (1 - zoneWidthRatio) / 2)).toInt()),
          (h * zoneHeightRatio)
              .toInt()
              .clamp(1, h - (h * (1 - zoneHeightRatio) / 2).toInt()),
        );

        final cellMat = binary.region(rect);

        // Binary ink is white after inverse thresholding. Count only actual
        // ink pixels: the external contour area of an unfilled printed ring
        // includes its empty center and can falsely grade it as marked.
        fillRatios.add(cv.countNonZero(cellMat) / (rect.width * rect.height));
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
