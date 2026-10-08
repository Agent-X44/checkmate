import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/services/cv/sheet_alignment_service.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'helpers/sheet_alignment_scenarios.dart';
import 'helpers/sheet_qr_fixture.dart';
import 'helpers/sheet_native_checks.dart';
import 'helpers/bubble_native_checks.dart';
import 'helpers/live_tracking_native_checks.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';

/// Android regression runner for machines without a desktop C++ toolchain.
/// Run: `flutter run -d <device> -t test/native_alignment_probe.dart`
/// A machine-readable ALIGNMENT_PROBE summary is printed to the device log.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var passed = 0;
  var failed = 0;
  Future<void> report(String name, FutureOr<String?> Function() check) async {
    String? error;
    try {
      error = await check();
    } catch (exception, stack) {
      error = '$exception\n$stack';
    }
    if (error == null) {
      passed++;
    } else {
      failed++;
    }
    // ignore: avoid_print
    print('ALIGNMENT_PROBE ${error == null ? 'PASS' : 'FAIL'} $name: '
        '${error ?? 'verified'}');
  }

  for (final bubbleCase in checkBubbleDensityCases().entries) {
    await report('bubble density: ${bubbleCase.key}', () => bubbleCase.value);
  }

  for (final layout in sheetLayouts) {
    final bytes = await rootBundle.load(layout.asset);
    final artwork = cv.imdecode(bytes.buffer.asUint8List(), cv.IMREAD_COLOR);
    await report('${layout.asset} follows camera motion in preview',
        () => checkLiveTracking(artwork, layout));
    for (final scenario in captureScenarios) {
      final capture = captureArtwork(artwork, layout, scenario);
      List<SheetPoint>? actual;
      try {
        actual = SheetAlignmentService.detectMarkerPoints(capture.image,
            aspectRatio: layout.aspectRatio,
            diameterRatio: layout.diameterRatio);
        final error = checkAlignedCenters(actual, capture.expectedCenters) ??
            checkInteriorRegistration(actual, capture);
        if (error == null) {
          passed++;
        } else {
          failed++;
        }
        // ignore: avoid_print
        print('ALIGNMENT_PROBE ${error == null ? 'PASS' : 'FAIL'} '
            '${layout.asset} ${scenario.name}: ${error ?? 'all centers within 8px'}');
      } catch (error, stack) {
        failed++;
        // ignore: avoid_print
        print('ALIGNMENT_PROBE ERROR ${layout.asset} ${scenario.name}: '
            '$error\n$stack');
      } finally {
        capture.dispose();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await report('${layout.asset} missing marker rejects shading guide',
        () => checkMissingMarker(artwork, layout));
    await report('${layout.asset} partially clipped markers require retake',
        () => checkClippedMarkers(artwork, layout));
    final template = layout.asset.contains('30_questions')
        ? Standard30QuestionsTemplate()
        : Standard50QuestionsTemplate();
    await report(
        '${layout.asset} unreadable captured QR rejects locked identity',
        () => checkUnreadableIdentity(artwork, template));
    final qrRect = addPrintedSheetQr(artwork, template);
    for (final rotation in [
      -1,
      cv.ROTATE_90_CLOCKWISE,
      cv.ROTATE_180,
      cv.ROTATE_90_COUNTERCLOCKWISE,
    ]) {
      await report('${layout.asset} printed QR rotation $rotation',
          () => checkPrintedQr(artwork, qrRect, rotation));
    }
    final capture = captureArtwork(artwork, layout, captureScenarios.first);
    try {
      await report('${layout.asset} short Sheet ID and blank OMR items',
          () => checkUnfilledOmr(capture.image, template));
      await report('${layout.asset} captured Sheet ID mismatch',
          () => checkIdentityMismatch(capture.image, template));
    } finally {
      capture.dispose();
      qrRect.dispose();
    }
    if (template.totalQuestions == 30) {
      await report('two narrow sheets on one page select the expected QR',
          () => checkTwoSheetPage(artwork, layout, template));
    }
    final marked = artwork.clone();
    final expectedAnswers = addKnownMarks(marked, layout);
    for (final scenario in [
      captureScenarios[0],
      captureScenarios[1],
      captureScenarios[2],
      captureScenarios[4],
    ]) {
      final markedCapture = captureArtwork(marked, layout, scenario);
      try {
        await report(
            '${layout.asset} known answers at ${scenario.name}',
            () =>
                checkMarkedOmr(markedCapture.image, template, expectedAnswers));
      } finally {
        markedCapture.dispose();
      }
    }
    marked.dispose();
    artwork.dispose();
  }
  // ignore: avoid_print
  print('ALIGNMENT_PROBE COMPLETE passed=$passed failed=$failed');
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: Text('Alignment tests: $passed passed, $failed failed'))));
}
