import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/models/omr/bubble_sheet_template.dart';
import 'package:checkmate/models/omr/qr_data.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';
import 'package:checkmate/services/cv/qr_detection_service.dart';
import 'package:checkmate/services/image_processor.dart';
import 'package:checkmate/services/cv/sheet_alignment_service.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'sheet_alignment_scenarios.dart';
import 'sheet_qr_fixture.dart';

Future<String?> checkDeveloperLayoutCapture(cv.Mat artwork, SheetLayout layout,
    BubbleSheetTemplate actualTemplate) async {
  final preferred = actualTemplate.totalQuestions == 30
      ? Standard50QuestionsTemplate()
      : Standard30QuestionsTemplate();
  final profile = TemplateCalibration.fromTemplate(actualTemplate)
      .copyWith(name: 'Local ${actualTemplate.totalQuestions} profile');
  final wrongProfile = TemplateCalibration.fromTemplate(preferred)
      .copyWith(name: 'Wrong layout profile');
  final capture = captureArtwork(artwork, layout, captureScenarios.first);
  try {
    final (_, bytes) = cv.imencode('.png', capture.image);
    final result = await ImageProcessor.processOmr(OmrRequest(
        bytes: bytes,
        corners: const [],
        template: preferred,
        developerSandbox: true,
        calibration: wrongProfile,
        calibrationProfiles: [profile, wrongProfile]));
    if (result == null) return 'No offline capture result';
    if (result.templateId != actualTemplate.id ||
        result.questionCapacity != actualTemplate.totalQuestions ||
        result.results.length != actualTemplate.totalQuestions) {
      return 'Offline capture did not use the detected physical layout';
    }
    if (result.templateName != profile.name) {
      return 'The selected layout preset leaked into a different layout';
    }
    if (result.qrData != null) {
      return 'Offline capture resolved a real identity';
    }
    return null;
  } finally {
    capture.dispose();
  }
}

Future<String?> checkDeveloperMissingMarker(
    cv.Mat artwork, BubbleSheetTemplate preferred) async {
  final missing = artwork.clone();
  try {
    cv.rectangle(missing, cv.Rect(0, 0, 160, 160), cv.Scalar.all(255),
        thickness: -1);
    final (_, bytes) = cv.imencode('.png', missing);
    await ImageProcessor.processOmr(OmrRequest(
        bytes: bytes,
        corners: const [],
        template: preferred,
        developerSandbox: true));
    return 'Offline capture accepted a sheet with a missing registration marker';
  } on SheetAlignmentException {
    return null;
  } finally {
    missing.dispose();
  }
}

String? checkMissingMarker(cv.Mat artwork, SheetLayout layout) {
  final missing = artwork.clone();
  try {
    cv.rectangle(missing, cv.Rect(0, 0, 160, 160), cv.Scalar.all(255),
        thickness: -1);
    for (final qrCenter in [null, _fixtureQrCenter(layout)]) {
      final actual = SheetAlignmentService.detectMarkerPoints(missing,
          aspectRatio: layout.aspectRatio,
          diameterRatio: layout.diameterRatio,
          qrCenter: qrCenter);
      if (actual != null) {
        return 'Missing marker was replaced by another mark '
            '(QR anchor ${qrCenter == null ? 'absent' : 'present'})';
      }
    }
    return null;
  } finally {
    missing.dispose();
  }
}

String? checkClippedMarkers(cv.Mat artwork, SheetLayout layout) {
  // Cut through the left circles while leaving their centers visible.
  final left = (layout.centers.first.$1 -
          (layout.centers[1].$1 - layout.centers.first.$1) *
              layout.diameterRatio /
              4)
      .round();
  final region =
      artwork.region(cv.Rect(left, 0, artwork.width - left, artwork.height));
  final cropped = region.clone();
  region.dispose();
  try {
    final qr = _fixtureQrCenter(layout);
    for (final qrCenter in [null, SheetPoint(qr.x - left, qr.y)]) {
      final actual = SheetAlignmentService.detectMarkerPoints(cropped,
          aspectRatio: layout.aspectRatio,
          diameterRatio: layout.diameterRatio,
          qrCenter: qrCenter);
      if (actual != null) {
        return 'Partially clipped markers were accepted '
            '(QR anchor ${qrCenter == null ? 'absent' : 'present'})';
      }
    }
    return null;
  } finally {
    cropped.dispose();
  }
}

SheetPoint _fixtureQrCenter(SheetLayout layout) => SheetPoint(
    layout.centers[0].$1 + .8 * (layout.centers[1].$1 - layout.centers[0].$1),
    layout.centers[0].$2 + .12 * (layout.centers[3].$2 - layout.centers[0].$2));

String? checkPrintedQr(cv.Mat image, cv.Rect originalQr, int rotation) {
  final rotated = rotation == -1 ? image.clone() : cv.rotate(image, rotation);
  try {
    final result =
        QrDetectionService.detectWithCorners(rotated, fastMode: true);
    if (result == null) return 'Printed QR was not decoded';
    if (result.data.sheetIdentifier != 'CMTEST') {
      return 'Wrong Sheet ID ${result.data.sheetIdentifier}';
    }
    if (result.corners?.length != 8) return 'QR corners were not returned';
    final expected = [
      (originalQr.x, originalQr.y),
      (originalQr.x + originalQr.width - 1, originalQr.y),
      (
        originalQr.x + originalQr.width - 1,
        originalQr.y + originalQr.height - 1
      ),
      (originalQr.x, originalQr.y + originalQr.height - 1),
    ].map((p) {
      return switch (rotation) {
        cv.ROTATE_90_CLOCKWISE => (image.height - 1 - p.$2, p.$1),
        cv.ROTATE_90_COUNTERCLOCKWISE => (p.$2, image.width - 1 - p.$1),
        cv.ROTATE_180 => (image.width - 1 - p.$1, image.height - 1 - p.$2),
        _ => p,
      };
    }).toList();
    final corners = result.corners!;
    for (var i = 0; i < 8; i += 2) {
      final x = corners[i] * rotated.width;
      final y = corners[i + 1] * rotated.height;
      final distance = expected
          .map((p) => math.sqrt(math.pow(x - p.$1, 2) + math.pow(y - p.$2, 2)))
          .reduce(math.min);
      if (distance > 8) {
        return 'QR corner coordinate error ${distance.toStringAsFixed(2)}px';
      }
    }
    return null;
  } finally {
    rotated.dispose();
  }
}

QrData resolvedFixtureQr(BubbleSheetTemplate template, String id) => QrData(
    studentName: 'Alignment Regression',
    examCode: 'ASSESSMENT',
    course: 'Regression',
    examTitle: 'Printed sheet',
    sheetIdentifier: id,
    templateName: template.name);

Future<String?> checkUnfilledOmr(
    cv.Mat capture, BubbleSheetTemplate template) async {
  final (encoded, bytes) = cv.imencode('.png', capture);
  if (!encoded) return 'Capture encoding failed';
  final result = await ImageProcessor.processOmr(OmrRequest(
      bytes: bytes,
      // Intentionally wrong preview coordinates: still-photo alignment must
      // establish its own marker frame rather than reuse the live overlay.
      corners: [0, 0, 0.1, 0, 0.1, 0.1, 0, 0.1],
      template: template,
      expectedQr: resolvedFixtureQr(template, 'CMTEST')));
  if (result == null) return 'OMR returned no result';
  if (result.results.length != template.totalQuestions) {
    return 'Expected ${template.totalQuestions} items, got ${result.results.length}';
  }
  if (result.qrData?.sheetIdentifier != 'CMTEST') {
    return 'OMR lost the resolved short Sheet ID';
  }
  final filled = result.results.where((r) => r.isFilled || r.answer != null);
  if (filled.isNotEmpty) {
    return 'Blank artwork produced ${filled.length} falsely filled answers';
  }
  return null;
}

Future<String?> checkIdentityMismatch(
    cv.Mat capture, BubbleSheetTemplate template) async {
  final (encoded, bytes) = cv.imencode('.png', capture);
  if (!encoded) return 'Capture encoding failed';
  try {
    await ImageProcessor.processOmr(OmrRequest(
        bytes: bytes,
        corners: const [],
        template: template,
        expectedQr: resolvedFixtureQr(template, 'CMOTHR')));
    return 'Mismatched Sheet ID was accepted';
  } on SheetIdentityException {
    return null;
  }
}

Future<String?> checkUnreadableIdentity(
    cv.Mat artwork, BubbleSheetTemplate template) async {
  final (encoded, bytes) = cv.imencode('.png', artwork);
  if (!encoded) return 'Capture encoding failed';
  try {
    await ImageProcessor.processOmr(OmrRequest(
        bytes: bytes,
        corners: const [],
        template: template,
        expectedQr: resolvedFixtureQr(template, 'CMTEST')));
    return 'A locked preview identity was accepted without a readable capture QR';
  } on SheetIdentityException catch (error) {
    return error.unreadable
        ? null
        : 'Unreadable QR used the mismatched-ID error';
  }
}

/// Coordinates measured from the actual PNG artwork's printed bubble outlines.
/// Each sheet covers its first/last rows and a double mark in an interior row.
Map<int, List<String>> addKnownMarks(cv.Mat artwork, SheetLayout layout) {
  final marks = layout.asset.contains('50_questions')
      ? <(int, String, double, double)>[
          (1, 'A', 196.5, 621.5),
          (25, 'D', 449, 1293.5),
          (26, 'B', 759, 621.5),
          (50, 'C', 844.5, 1293.5),
          (12, 'A', 196.5, 938.5),
          (12, 'B', 280.5, 938.5),
        ]
      : <(int, String, double, double)>[
          (1, 'A', 352.5, 1224),
          (30, 'D', 1148.5, 3290),
          (15, 'B', 617, 2221.5),
          (16, 'C', 884.5, 2292.5),
          (12, 'A', 352.5, 2007.5),
          (12, 'D', 1148.5, 2007.5),
        ];
  final expected = <int, List<String>>{};
  for (final mark in marks) {
    cv.circle(artwork, cv.Point(mark.$3.round(), mark.$4.round()),
        layout.asset.contains('50_questions') ? 8 : 18, cv.Scalar.all(0),
        thickness: -1);
    expected.putIfAbsent(mark.$1, () => []).add(mark.$2);
  }
  return expected;
}

Future<String?> checkMarkedOmr(cv.Mat capture, BubbleSheetTemplate template,
    Map<int, List<String>> expected) async {
  final (encoded, bytes) = cv.imencode('.png', capture);
  if (!encoded) return 'Capture encoding failed';
  final result = await ImageProcessor.processOmr(OmrRequest(
      bytes: bytes,
      corners: const [],
      template: template,
      expectedQr: resolvedFixtureQr(template, 'CMTEST')));
  if (result == null || result.results.length != template.totalQuestions) {
    return 'Marked sheet did not produce ${template.totalQuestions} results';
  }
  for (var i = 0; i < result.results.length; i++) {
    final answers = expected[i + 1] ?? const <String>[];
    final actual = result.results[i];
    if (actual.answer != (answers.length == 1 ? answers.single : null) ||
        actual.isFilled != answers.isNotEmpty ||
        actual.isAmbiguous != (answers.length > 1) ||
        actual.multipleAnswers.join(',') != answers.join(',')) {
      return 'Question ${i + 1} expected $answers, got '
          'answer=${actual.answer}, filled=${actual.isFilled}, '
          'ambiguous=${actual.isAmbiguous}, multiple=${actual.multipleAnswers}';
    }
  }
  return null;
}

Future<String?> checkTwoSheetPage(
    cv.Mat artwork, SheetLayout layout, BubbleSheetTemplate template) async {
  final left = artwork.clone();
  final right = artwork.clone();
  final leftQr = addPrintedSheetQr(left, template, sheetId: 'CMOTHR');
  final rightQr = addPrintedSheetQr(right, template);
  const width = 760;
  final height = (artwork.height * width / artwork.width).round();
  final page = cv.Mat.fromScalar(
      height + 140, 1640, cv.MatType.CV_8UC3, cv.Scalar.all(255));
  final smallLeft = cv.resize(left, (width, height));
  final smallRight = cv.resize(right, (width, height));
  final leftRegion = page.region(cv.Rect(20, 70, width, height));
  final rightRegion = page.region(cv.Rect(860, 70, width, height));
  try {
    smallLeft.copyTo(leftRegion);
    smallRight.copyTo(rightRegion);
    final qr = QrDetectionService.detectMatchingSheet(page, 'CMTEST');
    if (qr?.data.sheetIdentifier != 'CMTEST' || qr?.corners?.length != 8) {
      return 'Two-sheet page did not resolve the selected right-hand QR';
    }
    final corners = qr!.corners!;
    final center = SheetPoint(
        (corners[0] + corners[2] + corners[4] + corners[6]) * page.width / 4,
        (corners[1] + corners[3] + corners[5] + corners[7]) * page.height / 4);
    final markers = SheetAlignmentService.detectMarkerPoints(page,
        aspectRatio: layout.aspectRatio,
        diameterRatio: layout.diameterRatio,
        qrCenter: center);
    if (markers == null || markers.any((p) => p.x < page.width / 2)) {
      return 'Selected QR was aligned to the wrong printed sheet';
    }
    final expected = layout.centers
        .map((p) => cv.Point((p.$1 * width / artwork.width + 860).round(),
            (p.$2 * height / artwork.height + 70).round()))
        .toList();
    final alignmentError = checkAlignedCenters(markers, expected);
    for (final point in expected) {
      point.dispose();
    }
    if (alignmentError != null) return alignmentError;
    return await checkUnfilledOmr(page, template);
  } finally {
    leftRegion.dispose();
    rightRegion.dispose();
    smallLeft.dispose();
    smallRight.dispose();
    page.dispose();
    leftQr.dispose();
    rightQr.dispose();
    left.dispose();
    right.dispose();
  }
}
