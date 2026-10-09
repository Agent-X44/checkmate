import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/bubble_result.dart';
import 'package:checkmate/models/omr/processed_sheet.dart';
import 'package:checkmate/screens/sheet_evaluation_screen.dart';
import 'sheet_evaluation_service_test.dart' show evaluationFixture;
import 'package:checkmate/config/app_build.dart';

const key = <Map<String, dynamic>>[
  {'correct_answer': 'A', 'question_type': 'MCQ'},
];

Future<void> openEvaluation(
  WidgetTester tester, {
  required Future<void> Function(ProcessedSheet) save,
  Future<List<Map<String, dynamic>>> Function(String)? questions,
  WidgetBuilder? toolsBuilder,
}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SheetEvaluationScreen(
                                sheet: evaluationFixture([
                                  BubbleResult(answer: 'A', confidence: .9)
                                ]),
                                metadata: const {
                                  'exam_id': 'exam-1',
                                  'set_type': 'A'
                                },
                                loadQuestions: questions ?? (_) async => key,
                                onEvaluated: save,
                                developerToolsBuilder: toolsBuilder,
                              ))),
                  child: const Text('Open evaluation'))))));
  await tester.tap(find.text('Open evaluation'));
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.tap(find.text('CONFIRM & CONTINUE'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('template tools follow edition and never save the draft',
      (tester) async {
    var saves = 0;
    await openEvaluation(tester,
        save: (_) async {
          saves++;
        },
        toolsBuilder: (_) =>
            const Scaffold(body: Text('Local template workspace')));
    expect(saves, 0);
    expect(find.byIcon(Icons.tune),
        AppBuild.developerTools ? findsOneWidget : findsNothing);
    if (AppBuild.developerTools) {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Local template workspace'), findsOneWidget);
      expect(saves, 0);
    }
  });

  testWidgets('evaluates as an unsaved draft until the instructor confirms',
      (tester) async {
    final saved = <ProcessedSheet>[];
    await openEvaluation(tester, save: (sheet) async {
      saved.add(sheet);
    });
    expect(saved, isEmpty);
    expect(find.text('Score: 1 / 1'), findsOneWidget);
    expect(find.textContaining('Not saved yet'), findsOneWidget);
    await confirm(tester);
    expect(saved.length, 1);
    expect(saved.single.toSyncResult()['score'], 1);
    expect(find.text('Open evaluation'), findsOneWidget);
  });

  testWidgets('retake discards the draft without saving', (tester) async {
    var writes = 0;
    await openEvaluation(tester, save: (_) async {
      writes++;
    });
    await tester.tap(find.text('RETAKE SHEET'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Open evaluation'), findsOneWidget);
  });

  testWidgets('back without confirming discards the draft', (tester) async {
    var writes = 0;
    await openEvaluation(tester, save: (_) async {
      writes++;
    });
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Open evaluation'), findsOneWidget);
  });

  testWidgets('invalid item count cannot be confirmed', (tester) async {
    var writes = 0;
    await openEvaluation(tester,
        questions: (_) async => [...key, ...key],
        save: (_) async {
          writes++;
        });
    expect(writes, 0);
    expect(find.textContaining('does not match'), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.text('CONFIRM & CONTINUE'), findsNothing);
    expect(find.text('RETAKE SHEET'), findsOneWidget);
  });

  testWidgets('failed save stays visible and confirm retries the same result',
      (tester) async {
    final attempts = <Map<String, dynamic>>[];
    var keyLoads = 0;
    await openEvaluation(tester, questions: (_) async {
      keyLoads++;
      return key;
    }, save: (sheet) async {
      attempts.add(sheet.toSyncResult());
      if (attempts.length == 1) throw StateError('disk failure');
    });
    await confirm(tester);
    expect(attempts.length, 1);
    expect(find.textContaining('Tap confirm to retry'), findsOneWidget);
    expect(find.text('Open evaluation'), findsNothing);
    await confirm(tester);
    expect(attempts.length, 2);
    expect(attempts[1], attempts[0]);
    expect(keyLoads, 1);
    expect(find.text('Open evaluation'), findsOneWidget);
  });

  testWidgets('repeated retry taps cannot start duplicate evaluations',
      (tester) async {
    final retryKey = Completer<List<Map<String, dynamic>>>();
    var keyLoads = 0;
    await openEvaluation(tester, questions: (_) {
      keyLoads++;
      if (keyLoads == 1) throw StateError('temporary key failure');
      return retryKey.future;
    }, save: (_) async {});
    final retry = tester
        .widget<TextButton>(find
            .ancestor(
              of: find.text('Retry evaluation'),
              matching:
                  find.byWidgetPredicate((widget) => widget is TextButton),
            )
            .first)
        .onPressed!;
    retry();
    retry();
    expect(keyLoads, 2);
    retryKey.complete(key);
    await tester.pumpAndSettle();
    expect(find.text('Score: 1 / 1'), findsOneWidget);
  });

  testWidgets('back waits for durable saving and cannot cancel a pending write',
      (tester) async {
    final write = Completer<void>();
    var writes = 0;
    await openEvaluation(tester, save: (_) {
      writes++;
      return write.future;
    });
    // Pending saving keeps a spinner active, so advance without
    // pumpAndSettle, which intentionally waits for all animations to stop.
    await tester.tap(find.text('CONFIRM & CONTINUE'));
    await tester.pump();
    expect(find.text('Saving evaluation...'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(writes, 1);
    write.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open evaluation'), findsOneWidget);
    expect(writes, 1);
  });

  testWidgets('closing before key verification never saves', (tester) async {
    final questions = Completer<List<Map<String, dynamic>>>();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: SheetEvaluationScreen(
      sheet: evaluationFixture([BubbleResult(answer: 'A', confidence: .9)]),
      metadata: const {'exam_id': 'exam-1'},
      loadQuestions: (_) => questions.future,
      onEvaluated: (_) async {
        writes++;
      },
    )));
    await tester.pumpWidget(const SizedBox());
    questions.complete(key);
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}
