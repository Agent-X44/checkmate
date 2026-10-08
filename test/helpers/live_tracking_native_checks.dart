import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'package:checkmate/services/cv/sheet_alignment_service.dart';
import 'package:checkmate/services/cv/live_scan_policy.dart';
import 'sheet_alignment_scenarios.dart';

/// Native regression for both shipped artworks. No backend or camera needed.
String? checkLiveTracking(cv.Mat artwork, SheetLayout layout) {
  final capture = captureArtwork(artwork, layout, captureScenarios.first);
  final scale = LiveScanPolicy.previewMaxDimension / capture.image.height;
  final preview = cv.resize(capture.image, (
    (capture.image.width * scale).round(),
    LiveScanPolicy.previewMaxDimension
  ));
  try {
    var previous = capture.expectedCenters
        .map((p) => SheetPoint(p.x * scale, p.y * scale))
        .toList();
    final times = <int>[];
    for (final delta in [0.0, 8.0, 16.0, 24.0, 16.0, 8.0, 0.0]) {
      final transform = cv.Mat.fromList(
          2, 3, cv.MatType.CV_64FC1, [1.0, 0.0, delta, 0.0, 1.0, delta / 2]);
      final moved =
          cv.warpAffine(preview, transform, (preview.width, preview.height));
      try {
        final shortEdge = math.min(previous[0].distanceTo(previous[1]),
            previous[1].distanceTo(previous[2]));
        final widestEdge = math.max(previous[0].distanceTo(previous[1]),
            previous[2].distanceTo(previous[3]));
        final radius = math
            .max(shortEdge * 0.22, widestEdge * layout.diameterRatio * 1.3)
            .clamp(24.0, 128.0);
        final clock = Stopwatch()..start();
        final candidates =
            SheetAlignmentService.findNearbyCandidates(moved, previous, radius);
        final current = FiducialGeometry.trackMarkers(previous, candidates,
            searchRadius: radius,
            aspectRatio: layout.aspectRatio,
            diameterRatio: layout.diameterRatio);
        times.add(clock.elapsedMicroseconds);
        if (current == null) return 'Lost markers at camera movement $delta';
        for (var i = 0; i < 4; i++) {
          final expected = SheetPoint(
              capture.expectedCenters[i].x * scale + delta,
              capture.expectedCenters[i].y * scale + delta / 2);
          if (current[i].distanceTo(expected) > 5) {
            return 'Marker $i trails the current frame';
          }
        }
        previous = current;
      } finally {
        moved.dispose();
        transform.dispose();
      }
    }
    // ignore: avoid_print
    print('LIVE_TRACKING_PROBE ${layout.asset} tracking microseconds=$times');
    return null;
  } finally {
    preview.dispose();
    capture.dispose();
  }
}
