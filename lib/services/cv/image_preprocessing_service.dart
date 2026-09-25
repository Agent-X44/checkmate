import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImagePreprocessingService {
  static cv.Mat prepareForQrSearch(cv.Mat input) {
    final gray = input.channels == 3 ? cv.cvtColor(input, cv.COLOR_BGR2GRAY) : input;
    final blurred = cv.gaussianBlur(gray, (5, 5), 1.5);
    final binary = cv.adaptiveThreshold(
      blurred,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY_INV,
      31,
      10,
    );

    if (gray != input) {
    }
    return binary;
  }
}
