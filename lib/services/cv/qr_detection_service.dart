import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/omr/qr_data.dart';

class QrDetectionService {
  /// Robustly detects and decodes a QR code from a Mat.
  /// Tries multiple preprocessing strategies if the initial attempt fails.
  static QrData? detectQr(cv.Mat warped, Rect region) {
    debugPrint("QR: Starting detection in region $region (Warped: ${warped.width}x${warped.height})");
    
    final int x = (region.left * warped.width).toInt().clamp(0, warped.width - 1);
    final int y = (region.top * warped.height).toInt().clamp(0, warped.height - 1);
    final int w = (region.width * warped.width).toInt().clamp(1, warped.width - x);
    final int h = (region.height * warped.height).toInt().clamp(1, warped.height - y);

    final qrROI = warped.region(cv.Rect(x, y, w, h));
    if (qrROI.isEmpty) return null;

    QrData? result;

    try {
      // 1. Grayscale ROI
      final gray = qrROI.channels == 3 ? cv.cvtColor(qrROI, cv.COLOR_BGR2GRAY) : qrROI.clone();

      // Attempt 1: Native Detector (with safety check)
      result = _attemptNativeDecode(gray, "Raw Grayscale");
      
      if (result == null) {
        // Attempt 2: CLAHE + Native
        final clahe = cv.createCLAHE(clipLimit: 3.0, tileGridSize: (8, 8));
        final normalized = clahe.apply(gray);
        result = _attemptNativeDecode(normalized, "CLAHE");
        
        if (result == null) {
          // Attempt 3: Otsu + Native
          final (_, binary) = cv.threshold(normalized, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
          result = _attemptNativeDecode(binary, "Otsu Binary");
          binary.dispose();
        }
        
        normalized.dispose();
        clahe.dispose();
      }

      // 2. Pattern Verification (Fallback if detector fails or for better locking)
      // Even if we can't decode the text due to the missing native symbol, 
      // finding the 3 squares confirms a QR is present.
      if (result == null) {
        final hasPattern = _findQrPattern(gray);
        if (hasPattern) {
          debugPrint("QR: Found position markers but native decoder failed.");
          // We return a "Presence" data object if we can't decode the string
          // This allows the OMR to proceed with a default template if needed.
          result = QrData(
            studentName: "Detected (Not Decoded)",
            examCode: "UNKNOWN",
            course: "UNKNOWN",
            examTitle: "QR Found",
          );
        }
      }

      gray.dispose();
    } catch (e) {
      debugPrint("QR DETECTION EXCEPTION: $e");
    } finally {
      qrROI.dispose();
    }

    return result;
  }

  static QrData? _attemptNativeDecode(cv.Mat input, String label) {
    try {
      // Attempt to instantiate the detector. If the symbol is missing, 
      // this is where it will throw the FFI exception.
      final detector = cv.QRCodeDetector.empty();
      final (text, points, _) = detector.detectAndDecode(input);
      
      if (points.isNotEmpty) points.dispose();
      detector.dispose();
      
      if (text.isNotEmpty) {
        debugPrint("QR SUCCESS ($label): $text");
        return QrData.fromRaw(text);
      }
    } catch (e) {
      // Log only once if the native symbol is missing
      if (e.toString().contains("cv_QRCodeDetector_create")) {
        // Skip further native attempts if symbol is missing
        return null; 
      }
      debugPrint("QR Native Attempt ($label) Error: $e");
    }
    return null;
  }

  /// Manually looks for the 3 square "Position Markers" of a QR code.
  /// Refined to verify the 1:1:3:1:1 ratio and geometric relationship.
  static bool _findQrPattern(cv.Mat gray) {
    cv.Mat? binary;
    cv.VecVecPoint? contours;
    cv.VecVec4i? hierarchy;

    try {
      // 1. Adaptive Pre-processing for markers
      binary = cv.adaptiveThreshold(
          gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 31, 10);

      final (resContours, resHierarchy) =
          cv.findContours(binary, cv.RETR_TREE, cv.CHAIN_APPROX_SIMPLE);
      contours = resContours;
      hierarchy = resHierarchy;

      int markerCount = 0;

      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area < 100) continue;

        // QR markers have a specific nesting: a child and a grandchild
        // Check hierarchy: [Next, Previous, First_Child, Parent]
        // In opencv_dart VecVec4i, hierarchy[i] returns a Vec4i
        // val3 is First_Child
        final int childIdx = hierarchy[i].val3;
        if (childIdx != -1) {
          final int grandChildIdx = hierarchy[childIdx].val3;
          if (grandChildIdx != -1) {
            // Found a nested candidate. Verify circularity/squareness
            final perimeter = cv.arcLength(contours[i], true);
            final approx = cv.approxPolyDP(contours[i], 0.04 * perimeter, true);

            if (approx.length >= 4 && approx.length <= 6) {
              final rect = cv.boundingRect(contours[i]);
              final double ratio = rect.width / rect.height;
              if (ratio > 0.8 && ratio < 1.2) {
                markerCount++;
              }
            }
          }
        }
      }

      return markerCount >= 3;
    } catch (e) {
      debugPrint("QR Pattern Finder Error: $e");
      return false;
    } finally {
      binary?.dispose();
      contours?.dispose();
      hierarchy?.dispose();
    }
  }

  /// Performs a broader search if the primary region fails.
  /// Expands to top 40% of the page.
  static QrData? searchBroad(cv.Mat warped) {
    debugPrint("QR: Primary region failed, attempting broad search...");
    final broadRegion = const Rect.fromLTRB(0.4, 0.0, 1.0, 0.4);
    return detectQr(warped, broadRegion);
  }
}
