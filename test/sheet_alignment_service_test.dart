import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/services/cv/sheet_alignment_service.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'helpers/sheet_alignment_scenarios.dart';
import 'helpers/sheet_native_checks.dart';

// Exercises native contour extraction on both shipped artworks, including their
// filled shading example. Requires a native OpenCV test build.
// Android fallback: flutter run -d <device> -t test/native_alignment_probe.dart.
void main() {
  for (final layout in sheetLayouts) {
    for (final scenario in captureScenarios) {
      test('${layout.asset}: ${scenario.name}', () {
        final artwork = cv.imread(layout.asset);
        final capture = captureArtwork(artwork, layout, scenario);
        List<SheetPoint>? actual;
        try {
          actual = SheetAlignmentService.detectMarkerPoints(capture.image,
              aspectRatio: layout.aspectRatio,
              diameterRatio: layout.diameterRatio);
          expect(checkAlignedCenters(actual, capture.expectedCenters), isNull);
          expect(checkInteriorRegistration(actual, capture), isNull);
        } finally {
          capture.dispose();
          artwork.dispose();
        }
      });
    }
    test('${layout.asset}: missing marker cannot use the shading guide', () {
      final artwork = cv.imread(layout.asset);
      try {
        expect(checkMissingMarker(artwork, layout), isNull);
      } finally {
        artwork.dispose();
      }
    });
    test('${layout.asset}: clipped markers require another capture', () {
      final artwork = cv.imread(layout.asset);
      try {
        expect(checkClippedMarkers(artwork, layout), isNull);
      } finally {
        artwork.dispose();
      }
    });
  }
}
