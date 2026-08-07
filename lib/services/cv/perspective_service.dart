import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class PerspectiveService {
  /// Orders four points: [Top-Left, Top-Right, Bottom-Right, Bottom-Left].
  static cv.VecPoint orderPoints(cv.VecPoint pts) {
    if (pts.length != 4) return pts;
    final sorted = List<cv.Point>.from(pts.toList());

    sorted.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = sorted[0];
    final br = sorted[3];

    sorted.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final tr = sorted[0];
    final bl = sorted[3];

    return cv.VecPoint.fromList([tl, tr, br, bl]);
  }

  /// Performs a 4-point perspective transform to extract a rectangular paper image.
  /// [padding] allows expanding the destination points beyond the image boundaries (negative)
  /// or shrinking them inside (positive). For Pass 1 OMR, we use padding to ensure
  /// corner markers aren't clipped.
  static cv.Mat warpPaper(
      cv.Mat src, cv.VecPoint corners, double aspectRatio, int targetWidth,
      {double padding = 0.0}) {
    final orderedCorners = orderPoints(corners);

    final p1 = orderedCorners[0]; // tl
    final p2 = orderedCorners[1]; // tr
    final p3 = orderedCorners[2]; // br
    final p4 = orderedCorners[3]; // bl

    final double widthBottom =
        math.sqrt(math.pow(p3.x - p4.x, 2) + math.pow(p3.y - p4.y, 2));
    final double widthTop =
        math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
    final double maxWidth = math.max(widthBottom, widthTop);

    final double heightRight =
        math.sqrt(math.pow(p2.y - p3.y, 2) + math.pow(p2.x - p3.x, 2));
    final double heightLeft =
        math.sqrt(math.pow(p1.y - p4.y, 2) + math.pow(p1.x - p4.x, 2));
    final double maxHeight = math.max(heightRight, heightLeft);

    final double finalRatio =
        (aspectRatio > 0.1) ? aspectRatio : (maxWidth / maxHeight);
    final int targetHeight = (targetWidth / finalRatio).toInt();

    // Map source points to destination with padding.
    // If padding is 0.03 (3%), we shift the corners 3% inwards from the edges.
    final double offsetW = targetWidth * padding;
    final double offsetH = targetHeight * padding;

    final destPoints = cv.VecPoint.fromList([
      cv.Point(offsetW.toInt(), offsetH.toInt()),
      cv.Point((targetWidth - offsetW).toInt(), offsetH.toInt()),
      cv.Point(
          (targetWidth - offsetW).toInt(), (targetHeight - offsetH).toInt()),
      cv.Point(offsetW.toInt(), (targetHeight - offsetH).toInt()),
    ]);

    final M = cv.getPerspectiveTransform(orderedCorners, destPoints);
    final warped = cv.warpPerspective(src, M, (targetWidth, targetHeight));

    M.dispose();
    destPoints.dispose();

    return warped;
  }
}
