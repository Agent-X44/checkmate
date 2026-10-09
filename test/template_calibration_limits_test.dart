import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';

void main() {
  final valid =
      TemplateCalibration.fromTemplate(Standard30QuestionsTemplate()).toMap();

  test('a bubble grid slightly wider than its column box is accepted', () {
    final config = TemplateCalibration.fromMap(
        {...valid, 'gridStart': -.03, 'gridWidth': 1.08});
    expect(config.gridStart, -.03);
    expect(config.gridWidth, 1.08);
  });

  test('a grid that leaves the answer region is rejected', () {
    for (final change in [
      {'gridStart': .9, 'gridWidth': .65},
      {'gridStart': -.6, 'gridWidth': 1.0},
      {'gridStart': 0.0, 'gridWidth': 2.1},
      {'gridStart': -.5, 'gridWidth': .4},
    ]) {
      expect(() => TemplateCalibration.fromMap({...valid, ...change}),
          throwsFormatException);
    }
  });
}
