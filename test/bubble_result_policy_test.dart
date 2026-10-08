import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/bubble_result.dart';

void main() {
  test('ambiguous answers cannot receive credit through construction or copy',
      () {
    final result = BubbleResult(
        answer: 'A', confidence: 0.5, isAmbiguous: true, isCorrect: true);
    expect(result.isCorrect, isFalse);
    expect(result.copyWith(isCorrect: true).isCorrect, isFalse);
    expect(result.copyWith(isAmbiguous: false, isCorrect: true).isCorrect,
        isFalse);
    expect(result.toMap()['isCorrect'], isFalse);
  });

  test('multiple marks remain incorrect even if ambiguity is cleared', () {
    final result = BubbleResult(
        answer: 'A',
        confidence: 0.5,
        multipleAnswers: ['A', 'B'],
        isCorrect: true);
    expect(result.isAmbiguous, isTrue);
    final updated = result.copyWith(isAmbiguous: false, isCorrect: true);
    expect(updated.isAmbiguous, isTrue);
    expect(updated.isCorrect, isFalse);
  });

  test('a single unambiguous correct mark retains its credit', () {
    final result = BubbleResult(
        answer: 'A', confidence: 0.5, multipleAnswers: ['A'], isCorrect: true);
    expect(result.isCorrect, isTrue);
    expect(result.isAmbiguous, isFalse);
  });
}
