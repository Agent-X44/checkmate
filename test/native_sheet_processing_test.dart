import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/config/app_build.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';
import 'package:checkmate/services/image_processor.dart';
import 'helpers/bubble_native_checks.dart';
import 'helpers/sheet_alignment_scenarios.dart';
import 'helpers/sheet_native_checks.dart';
import 'helpers/sheet_qr_fixture.dart';

// Native OpenCV checks share their assertions with the Android runner, so
// development hosts without a desktop C++ toolchain can verify the same cases.
// A photo whose QR cannot be read runs every QR region, rotation and decoding
// strategy before asking for a retake, which is slow on shared CI runners.
const _exhaustiveQrSearch = Timeout.factor(3);

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
    if (AppBuild.developerTools) {
      test(
          '${layout.asset}: offline capture corrects a selected layout mismatch',
          () async {
        final artwork = cv.imread(layout.asset);
        try {
          expect(await checkDeveloperLayoutCapture(artwork, layout, template),
              isNull);
          expect(await checkDeveloperMissingMarker(artwork, template), isNull);
        } finally {
          artwork.dispose();
        }
      });
    }
    test('${layout.asset}: unreadable capture QR cannot reuse locked identity',
        () async {
      final artwork = cv.imread(layout.asset);
      try {
        expect(await checkUnreadableIdentity(artwork, template), isNull);
      } finally {
        artwork.dispose();
      }
    }, timeout: _exhaustiveQrSearch);
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
    // Grading requires a QR decoded from the photo itself (BR-05). At these
    // angles the far-corner QR modules shrink to about 1-1.6 px in a
    // 1200x1800 capture (the scanner's 1080p stills are similar), below what
    // any decoder can read, so the scanner must ask for a retake instead.
    final unreadableQr = template.totalQuestions == 30
        ? [captureScenarios[1], captureScenarios[2]]
        : [captureScenarios[2]];
    for (final scenario in unreadableQr) {
      test('${layout.asset}: unreadable QR at ${scenario.name} asks for a retake',
          () async {
        final artwork = cv.imread(layout.asset);
        final qr = addPrintedSheetQr(artwork, template);
        addKnownMarks(artwork, layout);
        final capture = captureArtwork(artwork, layout, scenario);
        try {
          final (_, bytes) = cv.imencode('.png', capture.image);
          await expectLater(
              ImageProcessor.processOmr(OmrRequest(
                  bytes: bytes,
                  corners: const [],
                  template: template,
                  expectedQr: resolvedFixtureQr(template, 'CMTEST'))),
              throwsA(isA<SheetIdentityException>()
                  .having((e) => e.unreadable, 'unreadable', isTrue)));
        } finally {
          capture.dispose();
          qr.dispose();
          artwork.dispose();
        }
      }, timeout: _exhaustiveQrSearch);
    }
    for (final scenario in [
      captureScenarios[0],
      captureScenarios[1],
      captureScenarios[2],
      captureScenarios[4],
    ].where((s) => !unreadableQr.contains(s))) {
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
