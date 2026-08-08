import 'package:opencv_dart/opencv_dart.dart' as cv;

class BubbleResult {
  final String? answer;
  final double confidence;
  final bool isFilled;
  final List<String> multipleAnswers;
  final bool isAmbiguous;

  BubbleResult({
    this.answer,
    required this.confidence,
    this.isFilled = false,
    this.multipleAnswers = const [],
    this.isAmbiguous = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'answer': answer,
      'confidence': confidence,
      'isFilled': isFilled,
      'multipleAnswers': multipleAnswers,
      'isAmbiguous': isAmbiguous,
    };
  }

  BubbleResult copyWith({
    String? answer,
    double? confidence,
    bool? isFilled,
    List<String>? multipleAnswers,
    bool? isAmbiguous,
  }) {
    return BubbleResult(
      answer: answer ?? this.answer,
      confidence: confidence ?? this.confidence,
      isFilled: isFilled ?? this.isFilled,
      multipleAnswers: multipleAnswers ?? this.multipleAnswers,
      isAmbiguous: isAmbiguous ?? this.isAmbiguous,
    );
  }
}

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
      gray.dispose();
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
        cellMat.dispose();
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

        // PRODUCTION REFINEMENT: Find the actual mass (bubble) within the zone
        // This handles minor grid misalignments.
        double fillRatio = 0;
        final (innerContours, _) =
            cv.findContours(cellMat, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

        if (innerContours.isNotEmpty) {
          double maxMassArea = 0;
          for (int j = 0; j < innerContours.length; j++) {
            final cArea = cv.contourArea(innerContours[j]);
            if (cArea > maxMassArea) maxMassArea = cArea;
          }
          // Use the largest detected mass for fill calculation
          fillRatio = maxMassArea / (rect.width * rect.height);
        } else {
          // Fallback to simple pixel count if no distinct contours found
          fillRatio = cv.countNonZero(cellMat) / (rect.width * rect.height);
        }

        fillRatios.add(fillRatio);
        cellMat.dispose();
      }
    }

    // 3. IDENTIFY ALL FILLED BUBBLES
    final List<int> filledIndices = [];
    for (int i = 0; i < fillRatios.length; i++) {
      if (fillRatios[i] > threshold) {
        filledIndices.add(i);
      }
    }

    binary.dispose();

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
