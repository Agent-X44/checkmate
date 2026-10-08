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

void main() {
  testWidgets(
      'template tools follow edition and never duplicate the saved result',
      (tester) async {
    var saves = 0;
    await openEvaluation(tester,
        save: (_) async {
          saves++;
        },
        toolsBuilder: (_) =>
            const Scaffold(body: Text('Local template workspace')));
    expect(saves, 1);
    expect(find.byIcon(Icons.tune),
        AppBuild.developerTools ? findsOneWidget : findsNothing);
    if (AppBuild.developerTools) {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Local template workspace'), findsOneWidget);
      expect(saves, 1);
    }
  });

  testWidgets('saves automatically once; continue only navigates',
      (tester) async {
    final saved = <ProcessedSheet>[];
    await openEvaluation(tester, save: (sheet) async {
      saved.add(sheet);
    });
    expect(saved.length, 1);
    expect(saved.single.toSyncResult()['score'], 1);
    expect(find.text('Saved on this device. Syncs automatically.'),
        findsOneWidget);
    expect(find.textContaining('CONFIRM'), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
    await tester.tap(find.text('CONTINUE SCANNING'));
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(find.text('Open evaluation'), findsOneWidget);
  });

  testWidgets('invalid item count never invokes the save callback',
      (tester) async {
    var writes = 0;
    await openEvaluation(tester,
        questions: (_) async => [...key, ...key],
        save: (_) async {
          writes++;
        });
    expect(writes, 0);
    expect(find.textContaining('does not match'), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.text('RETAKE SHEET'), findsOneWidget);
  });

  testWidgets(
      'failed local save is visible and retry saves the same evaluation',
      (tester) async {
    final attempts = <Map<String, dynamic>>[];
    var keyLoads = 0;
    await openEvaluation(tester, questions: (_) async {
      keyLoads++;
      return keyLoads == 1
          ? key
          : [
              {'correct_answer': 'B'}
            ];
    }, save: (sheet) async {
      attempts.add(sheet.toSyncResult());
      if (attempts.length == 1) throw StateError('disk failure');
    });
    expect(
        find.text('Saved on this device. Syncs automatically.'), findsNothing);
    expect(find.text('Retry evaluation'), findsOneWidget);
    await tester.tap(find.text('Retry evaluation'));
    await tester.pumpAndSettle();
    expect(attempts.length, 2);
    expect(attempts[1], attempts[0]);
    expect(keyLoads, 1);
    expect(find.text('Saved on this device. Syncs automatically.'),
        findsOneWidget);
  });

  testWidgets('repeated retry taps cannot start duplicate evaluations',
      (tester) async {
    final retryKey = Completer<List<Map<String, dynamic>>>();
    var keyLoads = 0;
    var writes = 0;
    await openEvaluation(tester, questions: (_) {
      keyLoads++;
      if (keyLoads == 1) throw StateError('temporary key failure');
      return retryKey.future;
    }, save: (_) async {
      writes++;
    });
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
    expect(writes, 1);
  });

  testWidgets('back waits for durable saving and cannot cancel a pending write',
      (tester) async {
    final write = Completer<void>();
    var writes = 0;
    // Pending saving keeps a spinner active, so advance the route without
    // pumpAndSettle, which intentionally waits for all animations to stop.
    await tester.pumpWidget(MaterialApp(
        home: SheetEvaluationScreen(
      sheet: evaluationFixture([BubbleResult(answer: 'A', confidence: .9)]),
      metadata: const {'exam_id': 'exam-1'},
      loadQuestions: (_) async => key,
      onEvaluated: (_) {
        writes++;
        return write.future;
      },
    )));
    await tester.pump();
    expect(find.text('Saving evaluation...'), findsOneWidget);
    final scope = tester.widget<PopScope>(find.byType(PopScope));
    expect(scope.canPop, isFalse);
    expect(writes, 1);
    write.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    expect(find.text('CONTINUE SCANNING'), findsOneWidget);
    expect(writes, 1);
  });

  testWidgets('closing before key verification does not save later',
      (tester) async {
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
