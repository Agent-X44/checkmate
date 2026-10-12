import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/services/cv/bubble_detection_service.dart';

void main() {
  const threshold = 0.365;
  List<int> marked(List<double> ratios) =>
      BubbleDetectionService.markedChoices(ratios, threshold);

  test('a fully shaded bubble is marked', () {
    expect(marked([0.00, 0.58, 0.00, 0.00]), [1]);
  });

  test('a small clear dot among clean blanks is marked', () {
    // Q8 D from a tablet capture: printed rings binarize to nothing, the
    // student's smaller dot covers just under the absolute threshold.
    expect(marked([0.00, 0.00, 0.00, 0.34]), [3]);
  });

  test('two dots in one question stay ambiguous', () {
    expect(marked([0.06, 0.55, 0.49, 0.02]), [1, 2]);
    expect(marked([0.00, 0.33, 0.30, 0.00]), [1, 2]);
  });

  test('dark printed rings do not lower the threshold', () {
    // Every blank ring covers about a quarter of its zone on some cameras.
    expect(marked([0.25, 0.27, 0.24, 0.26]), isEmpty);
    expect(marked([0.25, 0.34, 0.24, 0.26]), isEmpty);
    expect(marked([0.25, 0.62, 0.24, 0.26]), [1]);
  });

  test('faint smudges below 70% of the threshold are ignored', () {
    expect(marked([0.00, 0.20, 0.00, 0.00]), isEmpty);
    expect(marked([0.00, 0.00, 0.00, 0.00]), isEmpty);
  });
}
