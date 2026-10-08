import 'fiducial_geometry.dart';

/// Returns decoded QR corners in the original image, including when the
/// decoder searched a crop, a rotated frame, or a rectified quadrilateral.
class QrGeometry {
  static List<double>? normalizedCorners(
    List<SheetPoint> points, {
    required int width,
    required int height,
    double offsetX = 0,
    double offsetY = 0,
    int rotation = 0,
    List<SheetPoint>? warpedRegion,
    double warpedWidth = 300,
    double warpedHeight = 300,
  }) {
    if (points.length < 4 || width <= 0 || height <= 0) return null;
    SheetHomography? projection;
    if (warpedRegion != null) {
      if (warpedRegion.length != 4 || warpedWidth <= 0 || warpedHeight <= 0) {
        return null;
      }
      projection = SheetHomography.fromQuad(warpedRegion);
      if (projection == null) return null;
    }
    final result = <double>[];
    for (final point in points.take(4)) {
      final original = projection == null
          ? point
          : projection
              .unmap(SheetPoint(point.x / warpedWidth, point.y / warpedHeight));
      if (original == null) return null;
      var x = original.x + offsetX;
      var y = original.y + offsetY;
      if (rotation == 90) {
        final originalX = y;
        y = height - 1 - x;
        x = originalX;
      } else if (rotation == 270) {
        final originalX = width - 1 - y;
        y = x;
        x = originalX;
      } else if (rotation == 180) {
        x = width - 1 - x;
        y = height - 1 - y;
      }
      if (!x.isFinite || !y.isFinite) return null;
      result
          .addAll([(x / width).clamp(0.0, 1.0), (y / height).clamp(0.0, 1.0)]);
    }
    return result;
  }
}
