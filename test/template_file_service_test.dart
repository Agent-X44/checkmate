import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/services/template_file_service.dart';

void main() {
  final builtIn =
      TemplateCalibration.fromTemplate(Standard30QuestionsTemplate());

  test('exported files import back unchanged', () {
    final text = TemplateFileService.encode(builtIn);
    expect(text, contains('\n  "answerBubbles"'));
    final again = TemplateFileService.decode(text);
    expect(again.toMap(), builtIn.toMap());
    expect(again.answerBubbles.length, 120);
  });

  test('unknown keys from hand-edited files are ignored', () {
    final map = {...builtIn.toMap(), 'note': 'tuned on the Galaxy Tab'};
    final text = TemplateFileService.encode(TemplateCalibration.fromMap(map));
    expect(TemplateFileService.decode(text).name, builtIn.name);
  });

  test('invalid files explain what is wrong', () {
    expect(
        () => TemplateFileService.decode('{not json'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'This file is not valid JSON.')));
    expect(() => TemplateFileService.decode('[]'), throwsFormatException);
    expect(
        () => TemplateFileService.decode(TemplateFileService.encode(builtIn)
            .replaceFirst(
                '"fillThreshold": 0.3647299950348587', '"fillThreshold": 5')),
        throwsFormatException);
  });

  test('file names are safe slugs', () {
    expect(TemplateFileService.fileName(builtIn), 'standard-30-questions.json');
    expect(
        TemplateFileService.fileName(builtIn.copyWith(name: '  Tab #2 / dim ')),
        'tab-2-dim.json');
  });
}
