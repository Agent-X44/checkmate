import 'package:checkmate/screens/student_insight_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets(
        'shows MCQ, TF, incorrect, blank and ambiguous answers at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
        body: SingleChildScrollView(
            child: AnswerEvaluationList(answers: [
          {
            'question_number': 1,
            'question_text': 'Capital of France?',
            'answer': 'A',
            'correct_answer': 'A',
            'options': ['Paris', 'Rome'],
            'isCorrect': true
          },
          {
            'question_number': 2,
            'question_type': 'TF',
            'answer': 'B',
            'correct_answer': 'A',
            'isCorrect': false
          },
          {
            'question_number': 3,
            'answer': null,
            'correct_answer': 'B',
            'isCorrect': false
          },
          {
            'question_number': 4,
            'answer': null,
            'multipleAnswers': ['A', 'B'],
            'correct_answer': 'B',
            'isCorrect': false,
            'isAmbiguous': true
          },
        ])),
      )));
      expect(find.text('Capital of France?'), findsOneWidget);
      expect(find.text('Student answer: A. Paris'), findsOneWidget);
      expect(find.text('Student answer: False'), findsOneWidget);
      expect(find.text('Correct answer: True'), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Incorrect'), findsNWidgets(2));
      expect(find.text('Unanswered'), findsOneWidget);
      expect(find.text('Needs review'), findsNothing);
      expect(find.text('Student answer: A, B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'legacy result explains unavailable item details without inventing answers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: AnswerEvaluationList(answers: []),
    )));
    expect(find.textContaining('Item answers were not saved'), findsOneWidget);
    expect(find.textContaining('Question 1'), findsNothing);
  });
}
