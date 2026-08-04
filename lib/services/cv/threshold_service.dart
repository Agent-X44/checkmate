import 'package:opencv_dart/opencv_dart.dart' as cv;

class ThresholdService {
  /// Converts to binary using Otsu's thresholding.
  /// Reverted from Adaptive because Otsu was producing cleaner strips for this paper type.
  static cv.Mat applyOtsuThreshold(cv.Mat src, {double sigma = 0.2}) {
    // 1. Grayscale
    cv.Mat gray = src.channels == 3 ? cv.cvtColor(src, cv.COLOR_BGR2GRAY) : src.clone();

    // 2. Normalize Lighting (Keep CLAHE as it helps Otsu too)
    final clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
    final normalized = clahe.apply(gray);

    // 3. Noise Removal
    final blurred = cv.gaussianBlur(normalized, (5, 5), sigma);

    // 4. Otsu Thresholding
    final (_, binary) = cv.threshold(
      blurred,
      0,
      255,
      cv.THRESH_BINARY_INV + cv.THRESH_OTSU,
    );

    // 5. Noise Removal (Morphological Opening to remove paper grain)
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (2, 2));
    final clean = cv.morphologyEx(binary, cv.MORPH_OPEN, kernel);

    // Cleanup
    if (gray != src) gray.dispose();
    normalized.dispose();
    blurred.dispose();
    clahe.dispose();
    binary.dispose();
    kernel.dispose();

    return clean;
  }
}
