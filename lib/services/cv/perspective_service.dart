import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class PerspectiveService {
  /// Orders four points: [Top-Left, Top-Right, Bottom-Right, Bottom-Left].
  /// Uses a robust sum-difference method for consistent OMR mapping.
  static cv.VecPoint orderPoints(cv.VecPoint pts) {
    if (pts.length != 4) return pts;
    final points = pts.toList();

    // Sum-Difference method (very robust for paper-like rectangles)
    // TL: min(x+y), BR: max(x+y)
    // TR: min(y-x), BL: max(y-x)
    
    points.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = points[0];
    final br = points[3];

    final others = [points[1], points[2]];
    others.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final tr = others[0];
    final bl = others[1];

    return cv.VecPoint.fromList([tl, tr, br, bl]);
  }

  /// Calculates the destination points for a warped paper based on aspect ratio and padding.
  static cv.VecPoint getDestPoints(int targetWidth, int targetHeight, double padding) {
    final double offsetW = targetWidth * padding;
    final double offsetH = targetHeight * padding;

    return cv.VecPoint.fromList([
      cv.Point(offsetW.toInt(), offsetH.toInt()),
      cv.Point((targetWidth - offsetW).toInt(), offsetH.toInt()),
      cv.Point((targetWidth - offsetW).toInt(), (targetHeight - offsetH).toInt()),
      cv.Point(offsetW.toInt(), (targetHeight - offsetH).toInt()),
    ]);
  }

  /// Maps a list of points from one coordinate system to another using a transformation matrix.
  static List<cv.Point> transformPoints(List<cv.Point> pts, cv.Mat matrix) {
    if (pts.isEmpty) return [];
    
    try {
      // Ensure we get double values from the matrix (usually CV_64F)
      final m = List.generate(3, (r) => 
        List.generate(3, (c) => matrix.at<double>(r, c))
      );
      
      return pts.map((p) {
        final double x = p.x.toDouble();
        final double y = p.y.toDouble();
        final double w = m[2][0] * x + m[2][1] * y + m[2][2];
        if (w.abs() < 1e-9) return p;
        
        return cv.Point(
          ((m[0][0] * x + m[0][1] * y + m[0][2]) / w).round(),
          ((m[1][0] * x + m[1][1] * y + m[1][2]) / w).round(),
        );
      }).toList();
    } catch (e) {
      return pts;
    }
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
