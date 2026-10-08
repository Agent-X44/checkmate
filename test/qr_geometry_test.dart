import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'package:checkmate/services/cv/qr_geometry.dart';

void main() {
  const qr = [
    SheetPoint(700, 160),
    SheetPoint(820, 160),
    SheetPoint(820, 280),
    SheetPoint(700, 280),
  ];
  for (final rotation in [0, 90, 180, 270]) {
    test('QR crop restores original coordinates at rotation $rotation', () {
      // Independent forward rotation of a non-square camera image.
      SheetPoint rotate(SheetPoint p) => switch (rotation) {
            90 => SheetPoint(1599 - p.y, p.x),
            180 => SheetPoint(999 - p.x, 1599 - p.y),
            270 => SheetPoint(p.y, 999 - p.x),
            _ => p,
          };
      final cropped = qr.map((p) {
        final q = rotate(p);
        return SheetPoint(q.x - 40, q.y - 60);
      }).toList();
      final actual = QrGeometry.normalizedCorners(cropped,
          width: 1000,
          height: 1600,
          offsetX: 40,
          offsetY: 60,
          rotation: rotation)!;
      for (var i = 0; i < 4; i++) {
        expect(actual[i * 2], closeTo(qr[i].x / 1000, 1e-9));
        expect(actual[i * 2 + 1], closeTo(qr[i].y / 1600, 1e-9));
      }
    });
  }

  test('tilted header returns the QR location rather than the header frame',
      () {
    const header = [
      SheetPoint(100, 100),
      SheetPoint(900, 180),
      SheetPoint(950, 1300),
      SheetPoint(80, 1400),
    ];
    const decoded = [
      SheetPoint(210, 15),
      SheetPoint(270, 15),
      SheetPoint(270, 60),
      SheetPoint(210, 60),
    ];
    final actual = QrGeometry.normalizedCorners(decoded,
        width: 1200,
        height: 1800,
        offsetX: 25,
        offsetY: 50,
        warpedRegion: header)!;
    final sheetFrame = SheetHomography.fromQuad(header)!;
    for (var i = 0; i < 4; i++) {
      final projected =
          SheetPoint(actual[i * 2] * 1200 - 25, actual[i * 2 + 1] * 1800 - 50);
      final inHeader = sheetFrame.map(projected)!;
      expect(inHeader.x, closeTo(decoded[i].x / 300, 1e-9));
      expect(inHeader.y, closeTo(decoded[i].y / 300, 1e-9));
    }
    // Marker selection requires the QR in the upper-right header. Reporting
    // the enclosing rectangle's center places it near mid-sheet and rejects it.
    final center = SheetPoint(
        (actual[0] + actual[2] + actual[4] + actual[6]) * 1200 / 4 - 25,
        (actual[1] + actual[3] + actual[5] + actual[7]) * 1800 / 4 - 50);
    final normalizedCenter = sheetFrame.map(center)!;
    expect(normalizedCenter.x, greaterThan(0.7));
    expect(normalizedCenter.y, lessThan(0.25));
  });

  test('unusable decoded geometry does not invent a QR location', () {
    expect(QrGeometry.normalizedCorners([], width: 1000, height: 1600), isNull);
    expect(QrGeometry.normalizedCorners(qr, width: 0, height: 1600), isNull);
    expect(
        QrGeometry.normalizedCorners(qr,
            width: 1000,
            height: 1600,
            warpedRegion: List.filled(4, const SheetPoint(0, 0))),
        isNull);
  });
}
