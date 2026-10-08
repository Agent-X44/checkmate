import 'package:checkmate/services/cv/bubble_detection_service.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Native regression cases shared by the Android diagnostic runner.
Map<String, String?> checkBubbleDensityCases() {
  return {
    'blank printed rings': _checkRow(const [], isBinary: true),
    'one shaded bubble': _checkRow(const [2], isBinary: true),
    'multiple shaded bubbles remain ambiguous':
        _checkRow(const [0, 2], isBinary: true),
    'grayscale printed rings': _checkRow(const [], isBinary: false),
    'grayscale shaded bubble': _checkRow(const [1], isBinary: false),
  };
}

String? _checkRow(List<int> shaded, {required bool isBinary}) {
  // Each 100px cell is sampled in a 45px by 48px central zone. The ring's
  // enclosed disk exceeds the mark threshold but its actual outline does not.
  final binary = cv.Mat.zeros(80, 400, cv.MatType.CV_8UC1);
  cv.Mat? grayscale;
  try {
    for (var choice = 0; choice < 4; choice++) {
      final center = cv.Point(50 + choice * 100 + 3, 42);
      cv.circle(binary, center, 14, cv.Scalar.all(255),
          thickness: shaded.contains(choice) ? -1 : 2);
      if (!shaded.contains(choice)) {
        // Simulate ink from the printed choice label inside an empty ring.
        cv.line(binary, cv.Point(center.x - 3, center.y + 4),
            cv.Point(center.x, center.y - 4), cv.Scalar.all(255));
        cv.line(binary, cv.Point(center.x, center.y - 4),
            cv.Point(center.x + 3, center.y + 4), cv.Scalar.all(255));
      }
    }
    final input = isBinary ? binary : (grayscale = cv.bitwiseNOT(binary));
    final result = BubbleDetectionService.detectFilledBubble(input, 4,
        isBinary: isBinary, gridStart: 0, gridWidthRatio: 1);
    final answers = shaded.map((i) => String.fromCharCode(65 + i)).toList();
    final expectedAnswer = answers.length == 1 ? answers.single : null;
    if (result.answer != expectedAnswer ||
        result.isFilled != answers.isNotEmpty ||
        result.isAmbiguous != (answers.length > 1) ||
        result.multipleAnswers.join(',') != answers.join(',')) {
      return 'Expected $answers, got answer=${result.answer}, '
          'filled=${result.isFilled}, ambiguous=${result.isAmbiguous}, '
          'multiple=${result.multipleAnswers}';
    }
    return null;
  } finally {
    grayscale?.dispose();
    binary.dispose();
  }
}
