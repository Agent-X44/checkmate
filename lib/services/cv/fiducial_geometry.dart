import 'dart:math' as math;

typedef SheetPoint = math.Point<double>;

class FiducialCandidate {
  final SheetPoint center;
  final List<SheetPoint> outline;
  final double area;

  const FiducialCandidate(this.center, this.outline, this.area);
}

/// Geometry shared by camera detection and capture alignment. No native objects
/// are retained while testing marker combinations.
class FiducialGeometry {
  static List<SheetPoint> orderQuad(List<SheetPoint> points) {
    if (points.length != 4) throw ArgumentError('Expected four corners');
    final cx = points.fold<double>(0, (s, p) => s + p.x) / 4;
    final cy = points.fold<double>(0, (s, p) => s + p.y) / 4;
    final ordered = List<SheetPoint>.of(points)
      ..sort((a, b) => math
          .atan2(a.y - cy, a.x - cx)
          .compareTo(math.atan2(b.y - cy, b.x - cx)));
    var first = 0;
    for (var i = 1; i < 4; i++) {
      if (ordered[i].x + ordered[i].y < ordered[first].x + ordered[first].y) {
        first = i;
      }
    }
    return List.generate(4, (i) => ordered[(first + i) % 4]);
  }

  static bool isConvex(List<SheetPoint> points) {
    if (points.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      final c = points[(i + 2) % 4];
      if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 1e-6) {
        return false;
      }
    }
    return true;
  }

  static double polygonArea(List<SheetPoint> points) {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// The four printed circles must become equally sized round markers in the
  /// template's physical reference frame. This rejects an interior shading
  /// example even when it is itself a perfectly filled circle. Raw marker size
  /// and circularity are deliberately NOT required to match under perspective.
  static List<SheetPoint>? selectMarkers(
    List<FiducialCandidate> candidates, {
    required double imageArea,
    required double aspectRatio,
    required double diameterRatio,
    SheetPoint? qrCenter,
  }) {
    if (candidates.length < 4 ||
        !imageArea.isFinite ||
        imageArea <= 0 ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0 ||
        !diameterRatio.isFinite ||
        diameterRatio <= 0) {
      return null;
    }
    final markers = _shortlist(candidates);
    List<SheetPoint>? best;
    var bestScore = double.negativeInfinity;
    for (var a = 0; a < markers.length - 3; a++) {
      for (var b = a + 1; b < markers.length - 2; b++) {
        for (var c = b + 1; c < markers.length - 1; c++) {
          for (var d = c + 1; d < markers.length; d++) {
            final group = [markers[a], markers[b], markers[c], markers[d]];
            final quad = orderQuad(group.map((m) => m.center).toList());
            if (!isConvex(quad)) continue;
            final area = polygonArea(quad);
            // A selected narrow sheet can occupy very little of a two-sheet
            // photo at an extreme angle. Do not exclude its exact frame and
            // accidentally prefer a larger rectangle mixing both sheets.
            // QR position and physical marker sizes still validate its frame;
            // contour extraction separately requires resolved marker pixels.
            final minimumAreaRatio = qrCenter == null ? 0.025 : 0.0025;
            if (area < imageArea * minimumAreaRatio) continue;
            // Try both axis assignments: strong tilt can change which vertex
            // has the smallest x+y without changing the polygon's winding.
            for (var shift = 0; shift < (qrCenter == null ? 2 : 4); shift++) {
              var corners = List.generate(4, (i) => quad[(i + shift) % 4]);
              final transform = SheetHomography.fromQuad(corners);
              if (transform == null) continue;
              if (qrCenter != null) {
                final qr = transform.map(qrCenter);
                // Both shipped artworks print the identifying QR in the
                // upper-right header. This also selects the correct sheet
                // when two narrow sheets share one physical page.
                if (qr == null ||
                    qr.x < 0.5 ||
                    qr.x > 1.05 ||
                    qr.y < -0.05 ||
                    qr.y > 0.35) {
                  continue;
                }
              } else {
                // Without a QR location, a smaller answer-bubble rectangle
                // must not replace the outer registration frame. Ignore tiny
                // noise outside the frame, but require larger marks inside.
                final minimumArea = group.map((m) => m.area).reduce(math.min);
                final outside = candidates.any((m) {
                  if (m.area < minimumArea * 0.5) return false;
                  final p = transform.map(m.center);
                  return p == null ||
                      p.x < -0.08 ||
                      p.x > 1.08 ||
                      p.y < -0.08 ||
                      p.y > 1.08;
                });
                if (outside) continue;
              }
              // Most hypotheses fail their physical marker dimensions. Refine
              // only plausible frames to keep the bounded search inexpensive.
              if (_markerError(group, transform, aspectRatio, diameterRatio) ==
                  null) {
                continue;
              }
              final orderedMarkers = corners
                  .map((p) => group.firstWhere((m) => m.center == p))
                  .toList();
              corners = _refineCenters(corners, orderedMarkers);
              final refined = SheetHomography.fromQuad(corners);
              if (refined == null || !isConvex(corners)) continue;
              final error =
                  _markerError(group, refined, aspectRatio, diameterRatio);
              if (error == null) continue;
              // Printed marker dimensions are stronger evidence than frame
              // area: a larger rectangle of unrelated round background marks
              // must not displace a frame that matches the actual artwork.
              final score = -error + polygonArea(corners) / imageArea * 0.05;
              if (score > bestScore) {
                bestScore = score;
                best = corners;
              }
            }
          }
        }
      }
    }
    // Registration circles establish the axes but are symmetric under 180
    // degrees. Preserve the scanner's upright-sheet convention after selecting
    // the axis assignment; min(x+y) alone can start at a bottom vertex.
    if (qrCenter == null &&
        best != null &&
        best[0].y + best[1].y > best[2].y + best[3].y) {
      return [best[2], best[3], best[0], best[1]];
    }
    return best;
  }

  /// Follow an established frame using only candidates near each previous
  /// marker. Revalidate the same printed-circle geometry before accepting it.
  static List<SheetPoint>? trackMarkers(
    List<SheetPoint> previous,
    List<FiducialCandidate> candidates, {
    required double searchRadius,
    required double aspectRatio,
    required double diameterRatio,
  }) {
    if (previous.length != 4 || candidates.length < 4 || searchRadius <= 0) {
      return null;
    }
    final group = <FiducialCandidate>[];
    for (final point in previous) {
      FiducialCandidate? closest;
      var distance = searchRadius;
      for (final candidate in candidates) {
        if (group.contains(candidate)) continue;
        final delta = point.distanceTo(candidate.center);
        if (delta < distance) {
          closest = candidate;
          distance = delta;
        }
      }
      if (closest == null) return null;
      group.add(closest);
    }
    final corners = group.map((m) => m.center).toList();
    if (!isConvex(corners)) return null;
    final transform = SheetHomography.fromQuad(corners);
    if (transform == null ||
        _markerError(group, transform, aspectRatio, diameterRatio) == null) {
      return null;
    }
    final refined = _refineCenters(corners, group);
    final homography = SheetHomography.fromQuad(refined);
    if (!isConvex(refined) ||
        homography == null ||
        _markerError(group, homography, aspectRatio, diameterRatio) == null) {
      return null;
    }
    return refined;
  }

  /// Distant registration marks can be smaller than nearby shaded answers.
  /// Keep the boundaries of successive contour layers, so circular background
  /// clutter cannot consume the entire search budget before the sheet appears.
  /// Sampling each layer also bounds hypothesis work on cluttered captures.
  static List<FiducialCandidate> _shortlist(
      List<FiducialCandidate> candidates) {
    if (candidates.length <= 24) return List.of(candidates);
    final selected = <FiducialCandidate>{};
    final remaining = List<FiducialCandidate>.of(candidates);
    for (var layer = 0; layer < 3 && remaining.isNotEmpty; layer++) {
      final hull = _outerPoints(remaining.map((c) => c.center).toList());
      final boundary = remaining.where((c) => hull.contains(c.center)).toList();
      final cx =
          boundary.fold<double>(0, (s, c) => s + c.center.x) / boundary.length;
      final cy =
          boundary.fold<double>(0, (s, c) => s + c.center.y) / boundary.length;
      boundary.sort((a, b) => math
          .atan2(a.center.y - cy, a.center.x - cx)
          .compareTo(math.atan2(b.center.y - cy, b.center.x - cx)));
      final count = math.min(8, boundary.length);
      for (var i = 0; i < count && selected.length < 20; i++) {
        selected.add(boundary[i * boundary.length ~/ count]);
      }
      remaining.removeWhere((c) => hull.contains(c.center));
    }
    final largest = List<FiducialCandidate>.of(candidates)
      ..sort((a, b) => b.area.compareTo(a.area));
    for (final marker in largest) {
      if (selected.length >= 24) break;
      selected.add(marker);
    }
    return selected.toList();
  }

  static double? _markerError(
    List<FiducialCandidate> markers,
    SheetHomography transform,
    double aspectRatio,
    double diameterRatio,
  ) {
    final sizes = <double>[];
    var error = 0.0;
    for (final marker in markers) {
      if (marker.outline.length < 8) return null;
      final mapped = marker.outline.map(transform.map).toList();
      if (mapped.any((p) => p == null)) return null;
      final xs = mapped.map((p) => p!.x).toList();
      final ys = mapped.map((p) => p!.y / aspectRatio).toList();
      final width = xs.reduce(math.max) - xs.reduce(math.min);
      final height = ys.reduce(math.max) - ys.reduce(math.min);
      final size = (width + height) / 2;
      final outline = List.generate(xs.length, (i) => SheetPoint(xs[i], ys[i]));
      var perimeter = 0.0;
      for (var i = 0; i < outline.length; i++) {
        perimeter += outline[i].distanceTo(outline[(i + 1) % outline.length]);
      }
      final circularity =
          4 * math.pi * polygonArea(outline) / (perimeter * perimeter);
      if (!circularity.isFinite ||
          height <= 0 ||
          size < diameterRatio * 0.70 ||
          size > diameterRatio * 1.30 ||
          circularity < 0.80 ||
          width / height < 0.70 ||
          width / height > 1.43) {
        return null;
      }
      sizes.add(size);
      error += (size / diameterRatio - 1).abs() + (width / height - 1).abs();
    }
    return sizes.reduce(math.max) / sizes.reduce(math.min) > 1.40
        ? null
        : error;
  }

  /// An image ellipse's center is not the camera projection of its printed
  /// circle's center. At close range that difference can shift answer bubbles
  /// after the warp. Rectify each contour, find its area center, and project it
  /// back; repeating converges to the actual registration frame. Polygon area
  /// centers also tolerate the uneven sample spacing of native contours.
  static List<SheetPoint> _refineCenters(
    List<SheetPoint> initial,
    List<FiducialCandidate> markers,
  ) {
    var corners = initial;
    for (var iteration = 0; iteration < 6; iteration++) {
      final transform = SheetHomography.fromQuad(corners);
      if (transform == null) return initial;
      final next = <SheetPoint>[];
      for (var i = 0; i < 4; i++) {
        final mapped = markers[i].outline.map(transform.map).toList();
        if (mapped.any((p) => p == null)) return initial;
        final center = _areaCenter(mapped.cast<SheetPoint>());
        final projected = center == null ? null : transform.unmap(center);
        if (projected == null) return initial;
        next.add(projected);
      }
      // Preserve exact centers when their contours are already symmetric in
      // the sheet frame; subpixel changes below this level are insignificant.
      final movement = List.generate(4, (i) => next[i].distanceTo(corners[i]))
          .reduce(math.max);
      if (movement < 0.01) return corners;
      if (!isConvex(next)) return initial;
      corners = next;
    }
    return corners;
  }

  static SheetPoint? _areaCenter(List<SheetPoint> outline) {
    var twiceArea = 0.0;
    var x = 0.0;
    var y = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      final cross = a.x * b.y - b.x * a.y;
      twiceArea += cross;
      x += (a.x + b.x) * cross;
      y += (a.y + b.y) * cross;
    }
    if (twiceArea.abs() < 1e-12) return null;
    final center = SheetPoint(x / (3 * twiceArea), y / (3 * twiceArea));
    return center.x.isFinite && center.y.isFinite ? center : null;
  }

  static Set<SheetPoint> _outerPoints(List<SheetPoint> points) {
    if (points.length <= 3) return points.toSet();
    points.sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    List<SheetPoint> chain(Iterable<SheetPoint> input) {
      final hull = <SheetPoint>[];
      for (final p in input) {
        while (hull.length >= 2) {
          final a = hull[hull.length - 2];
          final b = hull.last;
          if ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) > 0) break;
          hull.removeLast();
        }
        hull.add(p);
      }
      return hull;
    }

    return {...chain(points), ...chain(points.reversed)};
  }
}

/// Analytic inverse of the unit-square-to-quad projective mapping. Using doubles
/// avoids rounding small, foreshortened markers during hypothesis validation.
class SheetHomography {
  final List<double> matrix;
  final List<double> _forward;
  const SheetHomography._(this.matrix, this._forward);

  static SheetHomography? fromQuad(List<SheetPoint> p) {
    final dx1 = p[1].x - p[2].x;
    final dx2 = p[3].x - p[2].x;
    final dx3 = p[0].x - p[1].x + p[2].x - p[3].x;
    final dy1 = p[1].y - p[2].y;
    final dy2 = p[3].y - p[2].y;
    final dy3 = p[0].y - p[1].y + p[2].y - p[3].y;
    final det = dx1 * dy2 - dx2 * dy1;
    if (det.abs() < 1e-9) return null;
    final g = (dx3 * dy2 - dx2 * dy3) / det;
    final h = (dx1 * dy3 - dx3 * dy1) / det;
    final a = p[1].x - p[0].x + g * p[1].x;
    final b = p[3].x - p[0].x + h * p[3].x;
    final c = p[0].x;
    final d = p[1].y - p[0].y + g * p[1].y;
    final e = p[3].y - p[0].y + h * p[3].y;
    final f = p[0].y;
    final determinant = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g);
    if (determinant.abs() < 1e-9) return null;
    return SheetHomography._([
      (e - f * h) / determinant,
      (c * h - b) / determinant,
      (b * f - c * e) / determinant,
      (f * g - d) / determinant,
      (a - c * g) / determinant,
      (c * d - a * f) / determinant,
      (d * h - e * g) / determinant,
      (b * g - a * h) / determinant,
      (a * e - b * d) / determinant,
    ], [
      a,
      b,
      c,
      d,
      e,
      f,
      g,
      h,
      1
    ]);
  }

  SheetPoint? map(SheetPoint p) => _map(matrix, p);

  SheetPoint? unmap(SheetPoint p) => _map(_forward, p);

  static SheetPoint? _map(List<double> m, SheetPoint p) {
    final w = m[6] * p.x + m[7] * p.y + m[8];
    if (w.abs() < 1e-9) return null;
    final x = (m[0] * p.x + m[1] * p.y + m[2]) / w;
    final y = (m[3] * p.x + m[4] * p.y + m[5]) / w;
    return x.isFinite && y.isFinite ? SheetPoint(x, y) : null;
  }
}
