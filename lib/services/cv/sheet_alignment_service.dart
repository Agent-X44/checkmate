import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'fiducial_geometry.dart';
import '../../models/omr/bubble_sheet_template.dart';
import 'sheet_template_selection.dart';

/// Finds the four printed registration circles directly in the current image.
/// It does not depend on preview coordinates, paper/background contrast, or
/// fixed image quadrants, which all become unreliable with strong perspective.
class SheetAlignmentService {
  static TemplateMarkerMatch? detectTemplateMarkers(
    cv.Mat source, {
    required BubbleSheetTemplate preferred,
    bool developerSandbox = false,
    SheetPoint? qrCenter,
  }) {
    TemplateMarkerMatch? select(List<FiducialCandidate> candidates) =>
        SheetTemplateSelection.select(candidates,
            preferred: preferred,
            imageArea: (source.width * source.height).toDouble(),
            developerSandbox: developerSandbox,
            qrCenter: qrCenter);
    var match = select(findCandidates(source));
    match ??= select(findCandidates(source,
        maxDimension: 2400, thresholdWindows: const [151, 401]));
    return match;
  }

  static cv.VecPoint? detectMarkers(
    cv.Mat source, {
    required double aspectRatio,
    required double diameterRatio,
    SheetPoint? qrCenter,
  }) {
    final corners = detectMarkerPoints(source,
        aspectRatio: aspectRatio,
        diameterRatio: diameterRatio,
        qrCenter: qrCenter);
    return corners == null
        ? null
        : cv.VecPoint.fromList(
            corners.map((p) => cv.Point(p.x.round(), p.y.round())).toList());
  }

  /// Keeps subpixel marker centers for the grading transform. Rounding before
  /// warping magnifies localization error at a heavily foreshortened edge.
  static List<SheetPoint>? detectMarkerPoints(
    cv.Mat source, {
    required double aspectRatio,
    required double diameterRatio,
    SheetPoint? qrCenter,
  }) {
    List<SheetPoint>? select(List<FiducialCandidate> candidates) =>
        FiducialGeometry.selectMarkers(
          candidates,
          imageArea: (source.width * source.height).toDouble(),
          aspectRatio: aspectRatio,
          diameterRatio: diameterRatio,
          qrCenter: qrCenter,
        );
    var corners = select(findCandidates(source));
    // Keep the live detector inexpensive, but retry a still photo with more
    // detail when the distant circles have been reduced to only a few pixels.
    // A wider threshold window also retains filled centers in close-up shots.
    corners ??= select(findCandidates(source,
        maxDimension: 2400, thresholdWindows: const [151, 401]));
    return corners;
  }

  /// The preview follows four small regions rather than rescanning the whole
  /// page and testing thousands of marker combinations on every camera frame.
  static List<FiducialCandidate> findNearbyCandidates(
      cv.Mat source, List<SheetPoint> previous, double radius) {
    final candidates = <FiducialCandidate>[];
    for (final point in previous) {
      final left = (point.x - radius).floor().clamp(0, source.width - 1);
      final top = (point.y - radius).floor().clamp(0, source.height - 1);
      final right = (point.x + radius).ceil().clamp(left + 1, source.width);
      final bottom = (point.y + radius).ceil().clamp(top + 1, source.height);
      final region =
          source.region(cv.Rect(left, top, right - left, bottom - top));
      final found = findCandidates(region,
          thresholdWindows: const [], maxAreaRatio: 0.25);
      final offset = SheetPoint(left.toDouble(), top.toDouble());
      for (final candidate in found) {
        final center = candidate.center + offset;
        if (candidates.any((c) => c.center.distanceTo(center) < 4)) continue;
        candidates.add(FiducialCandidate(center,
            candidate.outline.map((p) => p + offset).toList(), candidate.area));
      }
    }
    return candidates;
  }

  static List<FiducialCandidate> findCandidates(cv.Mat source,
      {int maxDimension = 1400,
      List<int> thresholdWindows = const [151],
      double maxAreaRatio = 0.06}) {
    if (source.isEmpty) return [];
    final scale =
        math.min(1.0, maxDimension / math.max(source.width, source.height));
    final resized = scale < 1
        ? cv.resize(source,
            ((source.width * scale).round(), (source.height * scale).round()))
        : source;
    final gray = resized.channels == 1
        ? resized
        : cv.cvtColor(resized,
            resized.channels == 4 ? cv.COLOR_BGRA2GRAY : cv.COLOR_BGR2GRAY);
    final blurred = cv.gaussianBlur(gray, (3, 3), 0.8);
    final (_, otsu) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU);
    final binaries = [otsu];
    for (final window in thresholdWindows) {
      binaries.add(cv.adaptiveThreshold(blurred, 255,
          cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, window, 8));
    }
    final imageArea = (gray.width * gray.height).toDouble();
    final candidates = <FiducialCandidate>[];
    for (final binary in binaries) {
      // RETR_LIST also sees separate markers when another contour surrounds
      // the sheet; center-fill validation excludes outlined answer bubbles.
      final (contours, _) =
          cv.findContours(binary, cv.RETR_LIST, cv.CHAIN_APPROX_NONE);
      for (var i = 0; i < contours.length; i++) {
        final contour = contours[i];
        final area = cv.contourArea(contour);
        // A foreshortened far marker may be much smaller than the nearest
        // answer bubble. Its size is validated in the rectified sheet frame.
        if (area < 10 ||
            area > imageArea * maxAreaRatio ||
            contour.length < 8) {
          continue;
        }
        final ellipse = cv.fitEllipse(contour);
        final ew = ellipse.size.width;
        final eh = ellipse.size.height;
        if (math.min(ew, eh) < 3 ||
            math.min(ew, eh) / math.max(ew, eh) < 0.08) {
          continue;
        }
        final ellipseArea = math.pi * ew * eh / 4;
        if (area / ellipseArea < 0.75 || area / ellipseArea > 1.15) continue;
        final bounds = cv.boundingRect(contour);
        // Clipped markers have unreliable centers and must require a retake.
        if (bounds.x <= 0 ||
            bounds.y <= 0 ||
            bounds.x + bounds.width >= gray.width - 1 ||
            bounds.y + bounds.height >= gray.height - 1) {
          continue;
        }
        final cx = ellipse.center.x;
        final cy = ellipse.center.y;
        final radius = math.max(1, (math.min(ew, eh) * 0.18).round());
        final centerRegion = cv.Rect(cx.round() - radius, cy.round() - radius,
            radius * 2 + 1, radius * 2 + 1);
        if (centerRegion.x < 0 ||
            centerRegion.y < 0 ||
            centerRegion.x + centerRegion.width > binary.width ||
            centerRegion.y + centerRegion.height > binary.height) {
          continue;
        }
        final center = binary.region(centerRegion);
        if (cv.countNonZero(center) / (center.width * center.height) < 0.85) {
          continue;
        }
        final point = SheetPoint(cx / scale, cy / scale);
        if (candidates.any((c) => c.center.distanceTo(point) < 4 / scale)) {
          continue;
        }
        // Remove pixel stair-steps before measuring circularity after the
        // perspective transform. Sampling the raw chain exaggerates perimeter
        // on the tiny far circles and rejects otherwise valid captures.
        final smooth = cv.approxPolyDP(contour, 0.5, true);
        // A few-pixel ellipse may simplify to fewer vertices than geometric
        // validation needs. Preserve its full contour rather than rejecting a
        // physically valid distant marker solely because it was simplified.
        final outlineSource = smooth.length >= 8 ? smooth : contour;
        final sampleCount = math.min(64, outlineSource.length);
        final outline = List.generate(sampleCount, (j) {
          final p = outlineSource[j * outlineSource.length ~/ sampleCount];
          return SheetPoint(p.x / scale, p.y / scale);
        });
        candidates
            .add(FiducialCandidate(point, outline, area / (scale * scale)));
      }
    }
    return candidates;
  }
}
