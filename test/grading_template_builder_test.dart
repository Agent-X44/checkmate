import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/config/app_build.dart';
import 'package:checkmate/models/omr/processed_sheet.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/screens/grading_template_builder_screen.dart';

void main() {
  testWidgets('dragging a handle moves the bubble template it returns',
      (tester) async {
    if (!AppBuild.developerTools) return;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final template = Standard30QuestionsTemplate();
    final image = File('assets/30_questions.png').readAsBytesSync();
    TemplateCalibration? result;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async => result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GradingTemplateBuilderScreen(
                              sheet: ProcessedSheet(
                                  warpedImage: image,
                                  thresholdImage: image,
                                  answerRegion: Uint8List(0),
                                  questionImages: const [],
                                  results: const [],
                                  templateName: template.name),
                              template: template,
                              config:
                                  TemplateCalibration.fromTemplate(template)))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(find.text('USE THIS TEMPLATE'), findsOneWidget);

    expect(find.byKey(const ValueKey('anchor-0-3')), findsOneWidget);
    // Move like a finger: small steps with frames in between.
    final finger = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('anchor-0-0'))));
    for (var i = 0; i < 20; i++) {
      await finger.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('USE THIS TEMPLATE'));
    await tester.tap(find.text('USE THIS TEMPLATE'));
    await tester.pumpAndSettle();
    // The route was opened inside runAsync, so its result resumes there.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(result, isNotNull);
    final bubbles = result!.answerBubbles;
    expect(bubbles.length, 120);
    // The builder starts from the template's calibrated bubbles. The 80 px
    // drag on an 800 px-wide image moves first-row A by 0.1; last-row D stays.
    final start = template.answerBubbles!;
    expect(bubbles.first.dx, closeTo(start.first.dx + .1, .002));
    expect((bubbles.last - start.last).distance, lessThan(1e-9));
  });
}
