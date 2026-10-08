import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';

// Independent forward camera projections, including severe foreshortening.
SheetPoint project(SheetPoint p, List<double> m) {
  final w = m[6] * p.x + m[7] * p.y + 1;
  return SheetPoint((m[0] * p.x + m[1] * p.y + m[2]) / w,
      (m[3] * p.x + m[4] * p.y + m[5]) / w);
}

FiducialCandidate circle(
    SheetPoint center, double diameter, double ratio, List<double> camera,
    {int samples = 64}) {
  final outline = List.generate(samples, (i) {
    final angle = 2 * math.pi * i / samples;
    return project(
        SheetPoint(center.x + diameter / 2 * math.cos(angle),
            center.y + diameter / 2 * ratio * math.sin(angle)),
        camera);
  });
  return FiducialCandidate(
      project(center, camera), outline, FiducialGeometry.polygonArea(outline));
}

List<SheetPoint> cameraContour(List<SheetPoint> dense, int samples) {
  final lengths = List.generate(
      dense.length, (i) => dense[i].distanceTo(dense[(i + 1) % dense.length]));
  final perimeter = lengths.reduce((a, b) => a + b);
  var edge = 0;
  var startDistance = 0.0;
  return List.generate(samples, (i) {
    final distance = i * perimeter / samples;
    while (
        edge < dense.length - 1 && startDistance + lengths[edge] < distance) {
      startDistance += lengths[edge++];
    }
    final t = (distance - startDistance) / lengths[edge];
    final a = dense[edge];
    final b = dense[(edge + 1) % dense.length];
    return SheetPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  });
}

// The exact center of the projected conic, as returned by an ellipse fit. It
// intentionally differs from projecting the printed circle's center.
FiducialCandidate detectedEllipse(
    SheetPoint center, double diameter, double ratio, List<double> camera) {
  final marker = circle(center, diameter, ratio, camera);
  final r = diameter / 2;
  final k = camera[6] * center.x + camera[7] * center.y + 1;
  final u = camera[6] * r;
  final v = camera[7] * r * ratio;
  final denominator = k * k - u * u - v * v;
  double axisCenter(int offset) =>
      ((camera[offset] * center.x +
                  camera[offset + 1] * center.y +
                  camera[offset + 2]) *
              k -
          camera[offset] * r * u -
          camera[offset + 1] * r * ratio * v) /
      denominator;
  return FiducialCandidate(
      SheetPoint(axisCenter(0), axisCenter(3)), marker.outline, marker.area);
}

const frame = [
  SheetPoint(0, 0),
  SheetPoint(1, 0),
  SheetPoint(1, 1),
  SheetPoint(0, 1)
];

double cameraImageArea(List<FiducialCandidate> candidates) {
  final xs = candidates.expand((c) => c.outline.map((p) => p.x));
  final ys = candidates.expand((c) => c.outline.map((p) => p.y));
  return (xs.reduce(math.max) - xs.reduce(math.min) + 200) *
      (ys.reduce(math.max) - ys.reduce(math.min) + 200);
}

void expectCorners(List<SheetPoint>? actual, List<SheetPoint> expected) {
  expect(actual, isNotNull);
  for (var i = 0; i < 4; i++) {
    expect(actual![i].distanceTo(expected[i]), lessThan(0.01));
  }
}

void main() {
  group('Live marker tracking', () {
    for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
      final original = [
        300.0,
        0.0,
        200.0,
        0.0,
        300.0 / layout.$1,
        60.0,
        0.0,
        0.0
      ];
      final previous = frame.map((p) => project(p, original)).toList();
      for (final motion in {
        'pan': [300.0, 0.0, 223.0, 0.0, 300.0 / layout.$1, 76.0, 0.0, 0.0],
        'zoom': [315.0, 0.0, 194.0, 0.0, 315.0 / layout.$1, 50.0, 0.0, 0.0],
        'tilt': [300.0, 12.0, 212.0, 4.0, 300.0 / layout.$1, 67.0, 0.02, 0.01],
      }.entries) {
        test(
            '${layout.$1} follows ${motion.key} without averaging old positions',
            () {
          final candidates = frame
              .map((p) => circle(p, layout.$2, layout.$1, motion.value))
              .toList();
          final result = FiducialGeometry.trackMarkers(previous, candidates,
              searchRadius: 66,
              aspectRatio: layout.$1,
              diameterRatio: layout.$2);
          expectCorners(
              result, frame.map((p) => project(p, motion.value)).toList());
        });
      }
      test('${layout.$1} missing mark cannot reuse its old position', () {
        final candidates = frame
            .take(3)
            .map((p) => circle(p, layout.$2, layout.$1, original))
            .toList();
        expect(
            FiducialGeometry.trackMarkers(previous, candidates,
                searchRadius: 66,
                aspectRatio: layout.$1,
                diameterRatio: layout.$2),
            isNull);
      });
      test(
          '${layout.$1} small answer bubble cannot replace a registration mark',
          () {
        final candidates = frame
            .asMap()
            .entries
            .map((e) => circle(e.value, e.key == 2 ? layout.$2 / 3 : layout.$2,
                layout.$1, original))
            .toList();
        expect(
            FiducialGeometry.trackMarkers(previous, candidates,
                searchRadius: 66,
                aspectRatio: layout.$1,
                diameterRatio: layout.$2),
            isNull);
      });
      test('${layout.$1} large movement requires fresh acquisition', () {
        final shifted = List<double>.of(original)..[2] += 150;
        final candidates =
            frame.map((p) => circle(p, layout.$2, layout.$1, shifted)).toList();
        expect(
            FiducialGeometry.trackMarkers(previous, candidates,
                searchRadius: 66,
                aspectRatio: layout.$1,
                diameterRatio: layout.$2),
            isNull);
      });
    }
  });

  final cameras = <String, List<double>>{
    'front facing': [900, 0, 100, 0, 1320, 100, 0, 0],
    'medium perspective': [900, 180, 100, 50, 1300, 100, 0.55, 0.05],
    'extreme perspective': [1000, 300, 80, 80, 1500, 100, 2.4, 0.6],
    'opposite extreme perspective': [
      200,
      -160,
      650,
      -35,
      380,
      150,
      -0.6,
      -0.15
    ],
    'diamond rotation': [600, -780, 1000, 600, 780, 100, 0, 0],
  };
  for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
    for (final entry in cameras.entries) {
      test('${layout.$1} ${entry.key}: selects corners over shading guide', () {
        final camera = List<double>.of(entry.value);
        // Maintain the different physical height of the narrow artwork.
        camera[1] *= 0.681 / layout.$1;
        camera[4] *= 0.681 / layout.$1;
        final candidates = frame
            .map((p) => circle(p, layout.$2, layout.$1, camera))
            .toList()
          ..add(circle(const SheetPoint(0.58, 0.28), layout.$2 * 0.70,
              layout.$1, camera));
        final expected = frame.map((p) => project(p, camera)).toList();
        final actual = FiducialGeometry.selectMarkers(candidates,
            imageArea: cameraImageArea(candidates),
            aspectRatio: layout.$1,
            diameterRatio: layout.$2);
        expect(actual, isNotNull);
        // Winding and axis assignment must match; the starting vertex may
        // change with roll, but opposite vertices cannot be swapped.
        expect(actual!.map((p) => expected.indexOf(p)).toList(),
            anyOf(equals([0, 1, 2, 3]), equals([2, 3, 0, 1])));
      });
      test('${layout.$1} ${entry.key}: missing corner cannot use shading guide',
          () {
        final camera = List<double>.of(entry.value);
        camera[1] *= 0.681 / layout.$1;
        camera[4] *= 0.681 / layout.$1;
        final candidates = frame
            .skip(1)
            .map((p) => circle(p, layout.$2, layout.$1, camera))
            .toList()
          ..add(circle(const SheetPoint(0.58, 0.28), layout.$2 * 0.70,
              layout.$1, camera));
        expect(
            FiducialGeometry.selectMarkers(candidates,
                imageArea: cameraImageArea(candidates),
                aspectRatio: layout.$1,
                diameterRatio: layout.$2),
            isNull);
      });
    }
  }

  test('homography maps each corner to its corresponding unit-square vertex',
      () {
    final projected =
        frame.map((p) => project(p, cameras['extreme perspective']!)).toList();
    final transform = SheetHomography.fromQuad(projected)!;
    expectCorners(projected.map((p) => transform.map(p)!).toList(), frame);
    final middle = transform.map(project(
        const SheetPoint(0.37, 0.62), cameras['extreme perspective']!))!;
    expect(middle.x, closeTo(0.37, 1e-9));
    expect(middle.y, closeTo(0.62, 1e-9));
    expect(
        transform.unmap(middle)!.distanceTo(project(
            const SheetPoint(0.37, 0.62), cameras['extreme perspective']!)),
        lessThan(1e-9));
  });

  for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
    test(
        '${layout.$1}: corrects ellipse center bias at close extreme perspective',
        () {
      final camera = <double>[
        1800,
        500 * 0.681 / layout.$1,
        180,
        150,
        2200 * 0.681 / layout.$1,
        200,
        5,
        1.8,
      ];
      final candidates = frame
          .map((p) => detectedEllipse(p, layout.$2, layout.$1, camera))
          .toList();
      final expected = frame.map((p) => project(p, camera)).toList();
      expect(candidates[0].center.distanceTo(expected[0]), greaterThan(4));
      final actual = FiducialGeometry.selectMarkers(candidates,
          imageArea: cameraImageArea(candidates),
          aspectRatio: layout.$1,
          diameterRatio: layout.$2,
          qrCenter: project(const SheetPoint(0.8, 0.12), camera));
      expect(actual, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(actual![i].distanceTo(expected[i]), lessThan(0.2));
      }
      // Verify alignment where grades are read, beyond the corner matches.
      final aligned = SheetHomography.fromQuad(actual!)!;
      for (final bubble in [
        const SheetPoint(0.16, 0.43),
        const SheetPoint(0.73, 0.88),
      ]) {
        expect(aligned.map(project(bubble, camera))!.distanceTo(bubble),
            lessThan(0.0003));
      }
    });
    test('${layout.$1}: close perspective with evenly spaced image contours',
        () {
      final camera = <double>[
        1800,
        500 * 0.681 / layout.$1,
        180,
        150,
        2200 * 0.681 / layout.$1,
        200,
        5,
        1.8,
      ];
      final candidates = frame.map((p) {
        final ellipse = detectedEllipse(p, layout.$2, layout.$1, camera);
        final dense = circle(p, layout.$2, layout.$1, camera, samples: 2048);
        return FiducialCandidate(
            ellipse.center, cameraContour(dense.outline, 32), dense.area);
      }).toList();
      final actual = FiducialGeometry.selectMarkers(candidates,
          imageArea: cameraImageArea(candidates),
          aspectRatio: layout.$1,
          diameterRatio: layout.$2,
          qrCenter: project(const SheetPoint(0.8, 0.12), camera));
      expect(actual, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(actual![i].distanceTo(project(frame[i], camera)), lessThan(0.5));
      }
    });
  }

  test('keeps far markers when many nearer shaded answers have larger areas',
      () {
    final camera = cameras['extreme perspective']!;
    final candidates =
        frame.map((p) => circle(p, 0.063, 0.681, camera)).toList();
    for (var row = 0; row < 10; row++) {
      for (var column = 0; column < 4; column++) {
        candidates.add(circle(
            SheetPoint(0.12 + column * 0.1, 0.35 + row * 0.06),
            0.025,
            0.681,
            camera));
      }
    }
    expectCorners(
        FiducialGeometry.selectMarkers(candidates,
            imageArea: cameraImageArea(candidates),
            aspectRatio: 0.681,
            diameterRatio: 0.063),
        frame.map((p) => project(p, camera)).toList());
  });

  test('background contours cannot exhaust the marker search before the sheet',
      () {
    final camera = cameras['front facing']!;
    final candidates =
        frame.map((p) => detectedEllipse(p, 0.063, 0.681, camera)).toList();
    // All 32 larger distractors are on the global convex hull, putting the
    // actual sheet on its next layer. Area-only ranking loses all four marks.
    for (var i = 0; i < 32; i++) {
      final angle = 2 * math.pi * i / 32;
      candidates.add(circle(
          SheetPoint(0.5 + 1.3 * math.cos(angle), 0.5 + math.sin(angle)),
          0.09,
          0.681,
          camera));
    }
    expectCorners(
        FiducialGeometry.selectMarkers(candidates,
            imageArea: cameraImageArea(candidates),
            aspectRatio: 0.681,
            diameterRatio: 0.063,
            qrCenter: project(const SheetPoint(0.8, 0.12), camera)),
        frame.map((p) => project(p, camera)).toList());
  });

  test('orders extreme quadrilateral cyclically where sum extrema are adjacent',
      () {
    final points = [
      const SheetPoint(200, 100),
      const SheetPoint(800, 750),
      const SheetPoint(600, 900),
      const SheetPoint(0, 1000)
    ];
    final ordered = FiducialGeometry.orderQuad(
        [points[2], points[0], points[3], points[1]]);
    expect(ordered, points);
    expect(FiducialGeometry.isConvex(ordered), isTrue);
  });

  test('missing corner with many filled answers cannot select an interior grid',
      () {
    final camera = cameras['front facing']!;
    final candidates =
        frame.skip(1).map((p) => circle(p, 0.063, 0.681, camera)).toList();
    for (var row = 0; row < 10; row++) {
      for (var column = 0; column < 4; column++) {
        candidates.add(circle(
            SheetPoint(0.12 + column * 0.18, 0.35 + row * 0.06),
            0.018,
            0.681,
            camera));
      }
    }
    expect(
        FiducialGeometry.selectMarkers(candidates,
            imageArea: cameraImageArea(candidates),
            aspectRatio: 0.681,
            diameterRatio: 0.063),
        isNull);
  });

  test('QR location selects its own sheet on a page with two narrow sheets',
      () {
    final camera = cameras['front facing']!;
    final candidates = <FiducialCandidate>[];
    for (final offset in [0.0, 1.2]) {
      candidates.addAll(frame.map(
          (p) => circle(SheetPoint(p.x + offset, p.y), 0.090, 0.320, camera)));
    }
    final expected =
        frame.map((p) => project(SheetPoint(p.x + 1.2, p.y), camera)).toList();
    final actual = FiducialGeometry.selectMarkers(candidates,
        imageArea: cameraImageArea(candidates),
        aspectRatio: 0.320,
        diameterRatio: 0.090,
        qrCenter: project(const SheetPoint(2.0, 0.12), camera));
    expectCorners(actual, expected);
  });

  for (final camera in <List<double>>[
    [1000, 300, 80, 80, 1500, 100, 2.4, 0.6],
    [1800, 500, 180, 150, 2200, 200, 5, 1.8],
  ]) {
    test(
        'small QR-selected sheet at perspective ${camera[6]} uses its own frame',
        () {
      final candidates = <FiducialCandidate>[];
      for (final offset in [0.0, 1.2]) {
        candidates.addAll(frame.map((p) =>
            circle(SheetPoint(p.x + offset, p.y), 0.090, 0.320, camera)));
        for (var row = 0; row < 10; row++) {
          for (var column = 0; column < 4; column++) {
            candidates.add(circle(
                SheetPoint(offset + 0.12 + column * 0.18, 0.35 + row * 0.06),
                0.018,
                0.320,
                camera));
          }
        }
        candidates.add(circle(
            SheetPoint(offset + 0.58, 0.28), 0.090 * 0.70, 0.320, camera));
      }
      final expected = frame
          .map((p) => project(SheetPoint(p.x + 1.2, p.y), camera))
          .toList();
      final imageArea = cameraImageArea(candidates);
      expect(
          FiducialGeometry.polygonArea(expected) / imageArea, lessThan(0.025));
      final actual = FiducialGeometry.selectMarkers(candidates,
          imageArea: imageArea,
          aspectRatio: 0.320,
          diameterRatio: 0.090,
          qrCenter: project(const SheetPoint(2.0, 0.12), camera));
      expectCorners(actual, expected);
      final aligned = SheetHomography.fromQuad(actual!)!;
      final bubble = aligned.map(project(const SheetPoint(1.9, 0.8), camera))!;
      expect(bubble.distanceTo(const SheetPoint(0.7, 0.8)), lessThan(0.0003));
    });
  }

  test(
      'QR cannot replace a missing corner with a filled answer or shading guide',
      () {
    for (final layout in [(0.681, 0.063), (0.320, 0.090)]) {
      for (final base in [
        cameras['front facing']!,
        cameras['extreme perspective']!,
        <double>[1800, 500, 180, 150, 2200, 200, 5, 1.8],
      ]) {
        final camera = List<double>.of(base);
        camera[1] *= 0.681 / layout.$1;
        camera[4] *= 0.681 / layout.$1;
        for (var missing = 0; missing < 4; missing++) {
          final candidates = <FiducialCandidate>[
            for (var i = 0; i < 4; i++)
              if (i != missing) circle(frame[i], layout.$2, layout.$1, camera),
            circle(const SheetPoint(0.58, 0.28), layout.$2 * 0.70, layout.$1,
                camera),
            for (var row = 0; row < 10; row++)
              for (var column = 0; column < 4; column++)
                circle(SheetPoint(0.12 + column * 0.18, 0.35 + row * 0.06),
                    0.018, layout.$1, camera),
          ];
          expect(
              FiducialGeometry.selectMarkers(candidates,
                  imageArea: cameraImageArea(candidates),
                  aspectRatio: layout.$1,
                  diameterRatio: layout.$2,
                  qrCenter: project(const SheetPoint(0.8, 0.12), camera)),
              isNull,
              reason: 'Layout ${layout.$1}, perspective ${camera[6]}, '
                  'missing corner $missing');
        }
      }
    }
  });

  test('rejects degenerate or incomplete geometry', () {
    expect(FiducialGeometry.isConvex(List.filled(4, const SheetPoint(5, 5))),
        isFalse);
    expect(SheetHomography.fromQuad(List.filled(4, const SheetPoint(5, 5))),
        isNull);
    expect(
        FiducialGeometry.selectMarkers([],
            imageArea: 1000000, aspectRatio: 0.681, diameterRatio: 0.063),
        isNull);
  });
}
