import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/bubble_result.dart';
import 'package:checkmate/services/sheet_evaluation_service.dart';
import 'package:checkmate/widgets/sheet_overlay_view.dart';
import 'sheet_evaluation_service_test.dart' show evaluationFixture;

void main() {
  test('overlay marks follow the deterministic grade', () {
    final sheet = SheetEvaluationService.evaluate(
        evaluationFixture([
          BubbleResult(answer: 'A', confidence: .9, multipleAnswers: ['A']),
          BubbleResult(answer: 'B', confidence: .9, multipleAnswers: ['B']),
          BubbleResult(confidence: 0),
          BubbleResult(confidence: .1, multipleAnswers: ['A', 'C']),
        ]),
        [
          for (final answer in ['A', 'C', 'D', 'A'])
            {'question_type': 'MCQ', 'correct_answer': answer}
        ],
        setType: 'A');

    expect(bubbleMark(sheet, 0, 0), BubbleMark.correct);
    expect(bubbleMark(sheet, 0, 1), BubbleMark.empty);
    expect(bubbleMark(sheet, 1, 1), BubbleMark.wrong);
    expect(bubbleMark(sheet, 1, 2), BubbleMark.missedKey);
    expect(bubbleMark(sheet, 2, 3), BubbleMark.missedKey);
    expect(bubbleMark(sheet, 2, 0), BubbleMark.empty);
    // Ambiguous rows are wrong even when one mark matches the key.
    expect(bubbleMark(sheet, 3, 0), BubbleMark.wrong);
    expect(bubbleMark(sheet, 3, 2), BubbleMark.wrong);
  });

  test('ungraded previews show detected marks only', () {
    final sheet = evaluationFixture(
        [BubbleResult(answer: 'B', confidence: .9, multipleAnswers: ['B'])]);
    expect(bubbleMark(sheet, 0, 1), BubbleMark.detected);
    expect(bubbleMark(sheet, 0, 0), BubbleMark.empty);
  });
}
