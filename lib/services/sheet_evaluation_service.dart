import '../models/omr/processed_sheet.dart';
import 'exam_set_service.dart';

/// Grades the calibrated local detections without altering marks or geometry.
class SheetEvaluationService {
  static ProcessedSheet evaluate(
      ProcessedSheet sheet, List<Map<String, dynamic>> questions,
      {required String setType}) {
    if (questions.isEmpty) {
      throw const FormatException('The assessment answer key is unavailable.');
    }
    final hasUnusedPrintedRows =
        sheet.questionCapacity == sheet.results.length &&
            sheet.results.length > questions.length;
    if (questions.length != sheet.results.length && !hasUnusedPrintedRows) {
      throw const FormatException(
          'The detected item count does not match the assessment. Retake the sheet.');
    }
    final set = setType.trim().toUpperCase().replaceFirst('SET ', '');
    if (!['A', 'B', '1', '2'].contains(set)) {
      throw const FormatException('The printed assessment set is invalid.');
    }
    final key = set == 'B' || set == '2'
        ? ExamSetService.generateSetB(questions)
        : questions.map((q) => Map<String, dynamic>.from(q)).toList();
    final answers = <String>[];
    for (var index = 0; index < key.length; index++) {
      final question = key[index];
      final type = (question['question_type'] ??
              question['questionType'] ??
              (question['part'] == 2 ? 'TF' : 'MCQ'))
          .toString()
          .toUpperCase();
      var answer =
          (question['correct_answer'] ?? question['correctAnswer'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
      if (type == 'TF') {
        if (answer == 'TRUE') answer = 'A';
        if (answer == 'FALSE') answer = 'B';
      }
      if (!(type == 'TF' ? ['A', 'B'] : ['A', 'B', 'C', 'D'])
              .contains(answer) ||
          !['TF', 'MCQ'].contains(type)) {
        throw FormatException(
            'The answer key for question ${index + 1} is invalid.');
      }
      question['correct_answer'] = answer;
      question['question_type'] = type;
      answers.add(answer);
    }
    return sheet.copyWith(
      questionDetails: key,
      results: [
        for (var index = 0; index < questions.length; index++)
          sheet.results[index].copyWith(
            isCorrect: !sheet.results[index].isAmbiguous &&
                sheet.results[index].answer == answers[index],
          ),
      ],
    );
  }
}
