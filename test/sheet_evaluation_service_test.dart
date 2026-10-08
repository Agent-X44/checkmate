import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/bubble_result.dart';
import 'package:checkmate/models/omr/processed_sheet.dart';
import 'package:checkmate/services/exam_set_service.dart';
import 'package:checkmate/services/sheet_evaluation_service.dart';

ProcessedSheet evaluationFixture(List<BubbleResult> results) => ProcessedSheet(
    warpedImage: Uint8List.fromList([1, 2]),
    thresholdImage: Uint8List(0),
    answerRegion: Uint8List(0),
    questionImages: const [],
    results: results,
    templateName: 'Test');

void main() {
  test('scores original detections and preserves blanks and ambiguity', () {
    final sheet = evaluationFixture([
      BubbleResult(answer: 'A', confidence: .9),
      BubbleResult(answer: 'B', confidence: .9),
      BubbleResult(confidence: 0),
      BubbleResult(answer: 'A', confidence: .5, isAmbiguous: true),
    ]);
    final key = [
      {'id': '1', 'question_type': 'MCQ', 'correct_answer': 'A'},
      {'id': '2', 'question_type': 'TF', 'correct_answer': 'False'},
      {'id': '3', 'correct_answer': 'B'},
      {'id': '4', 'correct_answer': 'A'},
    ];
    final evaluated = SheetEvaluationService.evaluate(sheet, key, setType: 'A');
    expect(
        evaluated.results.map((r) => r.isCorrect), [true, true, false, false]);
    expect(evaluated.results.last.isAmbiguous, isTrue);
    expect(evaluated.warpedImage, same(sheet.warpedImage));
    expect(evaluated.results.map((r) => r.answer),
        sheet.results.map((r) => r.answer));
    expect(sheet.results.first.isCorrect, isNull);
    expect(key[1]['correct_answer'], 'False');
    expect(evaluated.questionDetails[1]['correct_answer'], 'B');
    expect(evaluated.toSyncResult()['score'], 2);
    expect(evaluated.toSyncResult().containsKey('warpedImage'), isFalse);
  });

  test('Set B grades and synchronizes the same shuffled question identities',
      () {
    final key = List.generate(
        10,
        (i) => <String, dynamic>{
              'id': '$i',
              'question_type': i < 5 ? 'MCQ' : 'TF',
              'correct_answer': i.isEven ? 'A' : 'B',
            });
    final shuffled = ExamSetService.generateSetB(key);
    final sheet = evaluationFixture(shuffled
        .map((q) =>
            BubbleResult(answer: q['correct_answer'] as String, confidence: .9))
        .toList());
    final evaluated = SheetEvaluationService.evaluate(sheet, key, setType: 'B');
    expect(evaluated.results.every((r) => r.isCorrect == true), isTrue);
    expect(evaluated.questionDetails.map((q) => q['id']),
        shuffled.map((q) => q['id']));
  });

  test('does not trim or pad a mismatched scan to manufacture a grade', () {
    final sheet =
        evaluationFixture([BubbleResult(answer: 'A', confidence: .9)]);
    expect(
        () => SheetEvaluationService.evaluate(
            sheet,
            [
              {'correct_answer': 'A'},
              {'correct_answer': 'B'},
            ],
            setType: 'A'),
        throwsFormatException);
    expect(sheet.results.length, 1);
  });

  test('missing answer key cannot be saved as an all-zero result', () {
    final sheet =
        evaluationFixture([BubbleResult(answer: 'A', confidence: .9)]);
    expect(() => SheetEvaluationService.evaluate(sheet, [], setType: 'A'),
        throwsFormatException);
  });

  test('short assessment ignores only verified unused printed rows', () {
    final sheet = evaluationFixture([
      BubbleResult(answer: 'A', confidence: .9),
      BubbleResult(answer: 'B', confidence: .9),
      BubbleResult(answer: 'A', confidence: .9),
    ]).copyWith(questionCapacity: 3);
    final evaluated = SheetEvaluationService.evaluate(
        sheet,
        [
          {'id': 'active', 'correct_answer': 'A'}
        ],
        setType: 'A');
    expect(evaluated.results.length, 1);
    expect(evaluated.toSyncResult()['total'], 1);
    expect(evaluated.toSyncResult()['score'], 1);
    expect(evaluated.questionCapacity, 3);
    expect(sheet.results.length, 3);
  });

  test('declared capacity cannot hide missing detected rows', () {
    final incomplete = evaluationFixture([
      BubbleResult(answer: 'A', confidence: .9),
      BubbleResult(answer: 'A', confidence: .9),
    ]).copyWith(questionCapacity: 3);
    expect(
        () => SheetEvaluationService.evaluate(
            incomplete,
            [
              {'correct_answer': 'A'}
            ],
            setType: 'A'),
        throwsFormatException);
  });

  test('invalid key or set stops automatic saving', () {
    final sheet =
        evaluationFixture([BubbleResult(answer: 'A', confidence: .9)]);
    for (final question in [
      <String, dynamic>{},
      {'question_type': 'TF', 'correct_answer': 'C'},
      {'question_type': 'ESSAY', 'correct_answer': 'A'},
    ]) {
      expect(
          () =>
              SheetEvaluationService.evaluate(sheet, [question], setType: 'A'),
          throwsFormatException);
    }
    expect(
        () => SheetEvaluationService.evaluate(
            sheet,
            [
              {'correct_answer': 'A'}
            ],
            setType: 'unknown'),
        throwsFormatException);
  });
}
