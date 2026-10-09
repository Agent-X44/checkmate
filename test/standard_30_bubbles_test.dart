import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';

void main() {
  final template = Standard30QuestionsTemplate();

  test('reproduces the calibrated 30-question bubble export', () {
    final bubbles = template.answerBubbles!;
    expect(bubbles.length, 120);
    // Values exported by the Grading Template Builder (question, choice).
    const exported = {
      (1, 0): Offset(0.2319350055594574, 0.3204569749188875),
      (1, 1): Offset(0.46249415403597105, 0.320484959295166),
      (2, 2): Offset(0.6930575906598436, 0.3403969257846445),
      (8, 1): Offset(0.46228304160478295, 0.4596829581039731),
      (15, 1): Offset(0.46207192917359485, 0.5988809569127802),
      (21, 3): Offset(0.9243871552581765, 0.718191644550557),
      (29, 2): Offset(0.6931733706385332, 0.8772644428410423),
      (30, 0): Offset(0.230061431999063, 0.8971763409090624),
      (30, 3): Offset(0.9247357721793066, 0.8971344669768322),
    };
    exported.forEach((key, value) {
      final (question, choice) = key;
      final actual = bubbles[(question - 1) * 4 + choice];
      expect((actual - value).distance, lessThan(1e-12),
          reason: 'Q$question choice $choice');
    });
    expect(template.bubbleRadius, 0.018380537654020722);
    expect(template.fillThreshold, 0.3647299950348587);
  });

  test('developer presets start from the built-in bubbles', () {
    final config = TemplateCalibration.fromTemplate(template);
    expect(config.answerBubbles, template.answerBubbles);
    expect(config.bubbleRadius, template.bubbleRadius);
    expect(config.fillThreshold, template.fillThreshold);
    expect(
        TemplateCalibration.fromMap(config.toMap()).answerBubbles.length, 120);
  });
}
