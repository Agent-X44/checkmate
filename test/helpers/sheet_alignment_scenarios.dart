import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/services/cv/perspective_service.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';

/// Real production artwork, rather than ideal circles on an empty background.
const sheetLayouts = [
  SheetLayout('assets/50_questions.png', 0.681, 0.063,
      [(50, 50), (1000, 50), (1000, 1447), (50, 1447)]),
  SheetLayout('assets/30_questions.png', 0.320, 0.090,
      [(90, 77), (1233, 77), (1233, 3654), (90, 3654)]),
];

class SheetLayout {
  final String asset;
  final double aspectRatio;
  final double diameterRatio;
  final List<(int, int)> centers;

  const SheetLayout(
      this.asset, this.aspectRatio, this.diameterRatio, this.centers);
}

class CaptureScenario {
  final String name;
  final List<(int, int)> corners;
  final bool shadow;
  final bool blur;

  const CaptureScenario(this.name, this.corners,
      {this.shadow = false, this.blur = false});
}

const captureScenarios = [
  CaptureScenario('ordinary perspective',
      [(200, 120), (1000, 150), (1020, 1650), (180, 1630)]),
  CaptureScenario('strong perspective',
      [(350, 180), (650, 330), (1050, 1400), (100, 1620)]),
  CaptureScenario('extreme perspective with small far markers',
      [(500, 100), (700, 260), (1100, 1500), (120, 1650)]),
  CaptureScenario('opposite extreme perspective',
      [(120, 120), (1120, 260), (770, 1700), (610, 1550)]),
  CaptureScenario('close capture with all markers near frame edges',
      [(4, 4), (1195, 4), (1195, 1795), (4, 1795)]),
  CaptureScenario('close capture with tilt',
      [(200, 5), (1160, 290), (1010, 1795), (5, 1570)]),
  CaptureScenario('uneven illumination at a strong angle',
      [(350, 180), (650, 330), (1050, 1400), (100, 1620)],
      shadow: true),
  CaptureScenario('mild camera blur at a strong angle',
      [(350, 180), (650, 330), (1050, 1400), (100, 1620)],
      blur: true),
];

class CapturedSheet {
  final cv.Mat image;
  final List<cv.Point> expectedCenters;
  final List<(SheetPoint, SheetPoint)> registrationSamples;

  CapturedSheet(this.image, this.expectedCenters, this.registrationSamples);

  void dispose() {
    image.dispose();
    for (final point in expectedCenters) {
      point.dispose();
    }
  }
}

CapturedSheet captureArtwork(
    cv.Mat artwork, SheetLayout layout, CaptureScenario scenario) {
  final source = cv.VecPoint.fromList([
    cv.Point(0, 0),
    cv.Point(artwork.width - 1, 0),
    cv.Point(artwork.width - 1, artwork.height - 1),
    cv.Point(0, artwork.height - 1),
  ]);
  final destination = cv.VecPoint.fromList(
      scenario.corners.map((p) => cv.Point(p.$1, p.$2)).toList());
  final transform = cv.getPerspectiveTransform(source, destination);
  final markerPoints = layout.centers.map((p) => cv.Point(p.$1, p.$2)).toList();
  var image = cv.warpPerspective(artwork, transform, (1200, 1800),
      borderValue: cv.Scalar.all(210));
  final expected = PerspectiveService.transformPoints(markerPoints, transform);
  final m = List.generate(3,
      (row) => List.generate(3, (column) => transform.at<double>(row, column)));
  final registrationSamples = <(SheetPoint, SheetPoint)>[];
  for (final x in [0.15, 0.40, 0.70, 0.90]) {
    for (final y in [0.40, 0.65, 0.90]) {
      final sx = layout.centers[0].$1 +
          x * (layout.centers[1].$1 - layout.centers[0].$1);
      final sy = layout.centers[0].$2 +
          y * (layout.centers[3].$2 - layout.centers[0].$2);
      final w = m[2][0] * sx + m[2][1] * sy + m[2][2];
      registrationSamples.add((
        SheetPoint((m[0][0] * sx + m[0][1] * sy + m[0][2]) / w,
            (m[1][0] * sx + m[1][1] * sy + m[1][2]) / w),
        SheetPoint(x, y)
      ));
    }
  }
  if (scenario.shadow) {
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    image.dispose();
    image = gray;
    final pixels = image.data;
    // Strong smooth illumination gradient: paper brightness varies 64-235.
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final gain = 0.20 + 0.68 * (x / image.width);
        final i = y * image.width + x;
        pixels[i] = (pixels[i] * gain + 12).round().clamp(0, 255);
      }
    }
  }
  if (scenario.blur) {
    final blurred = cv.gaussianBlur(image, (5, 5), 1.0);
    image.dispose();
    image = blurred;
  }
  source.dispose();
  destination.dispose();
  transform.dispose();
  for (final point in markerPoints) {
    point.dispose();
  }
  return CapturedSheet(image, expected, registrationSamples);
}

/// Returns a diagnostic so these native scenarios can also run on Android.
String? checkAlignedCenters(List<SheetPoint>? actual, List<cv.Point> expected,
    {double tolerance = 8}) {
  if (actual == null) return 'No alignment found';
  if (actual.length != 4) return 'Expected four markers, got ${actual.length}';
  for (var i = 0; i < 4; i++) {
    final dx = actual[i].x - expected[i].x;
    final dy = actual[i].y - expected[i].y;
    final error = math.sqrt((dx * dx + dy * dy).toDouble());
    if (error > tolerance) {
      return 'Marker $i error ${error.toStringAsFixed(2)}px: '
          'actual (${actual[i].x}, ${actual[i].y}), '
          'expected (${expected[i].x}, ${expected[i].y})';
    }
  }
  return null;
}

String? checkInteriorRegistration(
    List<SheetPoint>? actual, CapturedSheet capture,
    {double tolerance = 0.006}) {
  if (actual == null) return 'No alignment found';
  final rectification = SheetHomography.fromQuad(actual);
  if (rectification == null) return 'Alignment transform is singular';
  for (final sample in capture.registrationSamples) {
    final actualPoint = rectification.map(sample.$1);
    final error = actualPoint?.distanceTo(sample.$2) ?? double.infinity;
    if (error > tolerance) {
      return 'Interior sample (${sample.$2.x}, ${sample.$2.y}) '
          'registration error ${error.toStringAsFixed(4)} '
          'exceeds $tolerance of the marker frame';
    }
  }
  return null;
}
