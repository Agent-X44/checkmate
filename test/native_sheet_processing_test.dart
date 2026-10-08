import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';
import 'helpers/bubble_native_checks.dart';
import 'helpers/sheet_alignment_scenarios.dart';
import 'helpers/sheet_native_checks.dart';
import 'helpers/sheet_qr_fixture.dart';

// Native OpenCV checks share their assertions with the Android runner, so
// development hosts without a desktop C++ toolchain can verify the same cases.
void main() {
  test('pixel density preserves blank, shaded and ambiguous bubble results',
      () {
    for (final check in checkBubbleDensityCases().entries) {
      expect(check.value, isNull, reason: check.key);
    }
  });
  for (final layout in sheetLayouts) {
    final template = layout.asset.contains('30_questions')
        ? Standard30QuestionsTemplate()
        : Standard50QuestionsTemplate();
    test('${layout.asset}: unreadable capture QR cannot reuse locked identity',
        () async {
      final artwork = cv.imread(layout.asset);
      try {
        expect(await checkUnreadableIdentity(artwork, template), isNull);
      } finally {
        artwork.dispose();
      }
    });
    for (final rotation in [
      -1,
      cv.ROTATE_90_CLOCKWISE,
      cv.ROTATE_180,
      cv.ROTATE_90_COUNTERCLOCKWISE,
    ]) {
      test('${layout.asset}: printed QR rotation $rotation coordinates', () {
        final artwork = cv.imread(layout.asset);
        final qr = addPrintedSheetQr(artwork, template);
        try {
          expect(checkPrintedQr(artwork, qr, rotation), isNull);
        } finally {
          qr.dispose();
          artwork.dispose();
        }
      });
    }
    test('${layout.asset}: short Sheet ID produces all blank OMR items',
        () async {
      final artwork = cv.imread(layout.asset);
      final qr = addPrintedSheetQr(artwork, template);
      final capture = captureArtwork(artwork, layout, captureScenarios.first);
      try {
        expect(await checkUnfilledOmr(capture.image, template), isNull);
      } finally {
        capture.dispose();
        qr.dispose();
        artwork.dispose();
      }
    });
    test('${layout.asset}: captured Sheet ID mismatch prevents grading',
        () async {
      final artwork = cv.imread(layout.asset);
      final qr = addPrintedSheetQr(artwork, template);
      final capture = captureArtwork(artwork, layout, captureScenarios.first);
      try {
        expect(await checkIdentityMismatch(capture.image, template), isNull);
      } finally {
        capture.dispose();
        qr.dispose();
        artwork.dispose();
      }
    });
    if (template.totalQuestions == 30) {
      test('two narrow sheets on one page use the expected QR and marker frame',
          () async {
        final artwork = cv.imread(layout.asset);
        try {
          expect(await checkTwoSheetPage(artwork, layout, template), isNull);
        } finally {
          artwork.dispose();
        }
      });
    }
    for (final scenario in [
      captureScenarios[0],
      captureScenarios[1],
      captureScenarios[2],
      captureScenarios[4],
    ]) {
      test('${layout.asset}: known printed answers at ${scenario.name}',
          () async {
        final artwork = cv.imread(layout.asset);
        final qr = addPrintedSheetQr(artwork, template);
        final expected = addKnownMarks(artwork, layout);
        final capture = captureArtwork(artwork, layout, scenario);
        try {
          expect(
              await checkMarkedOmr(capture.image, template, expected), isNull);
        } finally {
          capture.dispose();
          qr.dispose();
          artwork.dispose();
        }
      });
    }
  }
}
