import 'package:opencv_dart/opencv_dart.dart' as cv;

class BubbleResult {
  final String? answer;
  final double confidence;
  BubbleResult({this.answer, required this.confidence});

  Map<String, dynamic> toMap() {
    return {
      'answer': answer,
      'confidence': confidence,
    };
  }
}

class BubbleDetectionService {
  /// Processes a single question row using HIGH-PRECISION GRID mapping.
  static BubbleResult detectFilledBubble(
    cv.Mat rowMat, 
    int choicesCount, 
    {
      bool isBinary = false, 
      double gridStart = 0.15, 
      double gridWidthRatio = 0.82,
      List<double>? customXOffsets, 
    }
  ) {
    cv.Mat binary;
    if (isBinary) {
      binary = rowMat.clone();
    } else {
      cv.Mat gray = rowMat.channels == 3 ? cv.cvtColor(rowMat, cv.COLOR_BGR2GRAY) : rowMat.clone();
      final (_, otsu) = cv.threshold(gray, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU);
      binary = otsu;
      gray.dispose();
    }

    final int w = binary.width;
    final int h = binary.height;

    final List<double> fillRatios = [];

    // 2. MEASURE DENSITY
    if (customXOffsets != null && customXOffsets.isNotEmpty) {
      // Use user-designed custom points from Template Designer
      for (double relX in customXOffsets) {
        final rect = cv.Rect(
          (relX * w - (w * 0.05)).toInt().clamp(0, w - 1), 
          (h * 0.15).toInt().clamp(0, h - 1),
          (w * 0.10).toInt().clamp(1, w - (relX * w - (w * 0.05)).toInt()),
          (h * 0.70).toInt().clamp(1, h - (h * 0.15).toInt()),
        );
        final cellMat = binary.region(rect);
        fillRatios.add(cv.countNonZero(cellMat) / (rect.width * rect.height));
        cellMat.dispose();
      }
    } else {
      // 1. DEFINE THE GRID:
      final double gridStartX = w * gridStart; 
      final double gridWidth = w * gridWidthRatio; 
      final double cellWidth = gridWidth / choicesCount;

      // 2. MEASURE DENSITY IN EACH CELL
      for (int i = 0; i < choicesCount; i++) {
        final double xStart = gridStartX + (i * cellWidth);

        // ULTRA-PRECISION SCAN: Focus ONLY on the center 45% of each cell.
        // This prevents "ink leakage" between neighboring bubbles.
        final rect = cv.Rect(
          (xStart + (cellWidth * 0.275)).toInt().clamp(0, w - 1),
          (h * 0.20).toInt().clamp(0, h - 1),
          (cellWidth * 0.45).toInt().clamp(1, w - (xStart + (cellWidth * 0.275)).toInt()),
          (h * 0.60).toInt().clamp(1, h - (h * 0.20).toInt()),
        );

        final cellMat = binary.region(rect);
        final double filledPixels = cv.countNonZero(cellMat).toDouble();
        final double totalPixels = (rect.width * rect.height).toDouble();

        fillRatios.add(filledPixels / totalPixels);
        cellMat.dispose();
      }
    }

    // 3. IDENTIFY THE WINNER
    int winnerIdx = -1;
    double maxFill = -1.0;
    double secondMaxFill = 0.0;

    for (int i = 0; i < fillRatios.length; i++) {
      if (fillRatios[i] > maxFill) {
        secondMaxFill = maxFill > 0 ? maxFill : 0.0;
        maxFill = fillRatios[i];
        winnerIdx = i;
      } else if (fillRatios[i] > secondMaxFill) {
        secondMaxFill = fillRatios[i];
      }
    }

    binary.dispose();

    // 4. MAP TO LETTER (A-E)
    final String letter = String.fromCharCode(65 + winnerIdx);
    double confidence = (maxFill - secondMaxFill).clamp(0.0, 1.0);

    return BubbleResult(
      // Robust threshold for filled bubble
      answer: maxFill > 0.15 ? letter : null,
      confidence: confidence,
    );
  }
}
