import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/services/exam_set_service.dart';

void main() {
  test('Set B shuffles inside parts without mixing MCQ and True/False', () {
    final original = <Map<String, dynamic>>[
      for (var i = 1; i <= 12; i++)
        {'id': 'mcq-$i', 'questionType': 'MCQ', 'part': 1},
      for (var i = 1; i <= 6; i++)
        {'id': 'tf-$i', 'questionType': 'TF', 'part': 2},
    ];

    final setB = ExamSetService.generateSetB(original);

    expect(setB, hasLength(18));
    expect(setB.take(12).every((q) => q['questionType'] == 'MCQ'), isTrue);
    expect(setB.skip(12).every((q) => q['questionType'] == 'TF'), isTrue);
    expect(setB.map((q) => q['id']).toSet(),
        original.map((q) => q['id']).toSet());
    expect(ExamSetService.generateSetB(original), setB);
  });

  test('Set B keeps database question_type rows in the same parts', () {
    final databaseRows = <Map<String, dynamic>>[
      {'id': '1', 'question_type': 'MCQ'},
      {'id': '2', 'question_type': 'TF'},
      {'id': '3', 'question_type': 'MCQ'},
      {'id': '4', 'question_type': 'TF'},
    ];
    final setB = ExamSetService.generateSetB(databaseRows);
    expect(setB.map((q) => q['id']).toSet(), {'1', '2', '3', '4'});
    expect(setB.take(2).every((q) => q['question_type'] == 'MCQ'), isTrue);
    expect(setB.skip(2).every((q) => q['question_type'] == 'TF'), isTrue);
  });
}
