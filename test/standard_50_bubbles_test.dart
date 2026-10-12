import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';

void main() {
  final template = Standard50QuestionsTemplate();

  test('50-question bubbles match the printed rings in the artwork', () {
    final bubbles = template.answerBubbles!;
    expect(bubbles.length, 200);
    // Artwork pixels (question, choice) of rings checked by hand, mapped
    // through the marker frame (49.5, 49.5)-(1000.5, 1446.5).
    const printed = {
      (1, 0): (196.5, 621.5),
      (12, 1): (280.5, 938.5),
      (25, 3): (449.0, 1293.5),
      (26, 1): (759.0, 621.5),
      (50, 2): (844.5, 1293.5),
    };
    printed.forEach((key, pixel) {
      final (question, choice) = key;
      final actual = bubbles[(question - 1) * 4 + choice];
      expect(actual.dx * 951 + 49.5, closeTo(pixel.$1, 1e-9),
          reason: 'Q$question choice $choice x');
      expect(actual.dy * 1397 + 49.5, closeTo(pixel.$2, 1e-9),
          reason: 'Q$question choice $choice y');
    });
  });
}
