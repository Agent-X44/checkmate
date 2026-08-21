import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/omr/qr_data.dart';

class QrDetectionService {
  static QrData? detectQr(cv.Mat warped, Rect region) {
    final int x = (region.left * warped.width).toInt().clamp(0, warped.width - 1);
    final int y = (region.top * warped.height).toInt().clamp(0, warped.height - 1);
    final int w = (region.width * warped.width).toInt().clamp(1, warped.width - x);
    final int h = (region.height * warped.height).toInt().clamp(1, warped.height - y);
    final qrROI = warped.region(cv.Rect(x, y, w, h));
    if (qrROI.isEmpty) return null;
    QrData? result;
    try {
      final gray = qrROI.channels == 3 ? cv.cvtColor(qrROI, cv.COLOR_BGR2GRAY) : qrROI.clone();
      result = _attemptNativeDecode(gray);
      if (result == null && _hasSquares(gray)) {
        result = QrData(
          studentName: "Detected",
          examCode: "UNKNOWN",
          course: "UNKNOWN",
          examTitle: "QR Found",
          sheetIdentifier: "UNKNOWN",
        );
      }
      gray.dispose();
    } catch (_) {} finally {
      qrROI.dispose();
    }
    return result;
  }

  static QrData? _attemptNativeDecode(cv.Mat input) {
    try {
      final detector = cv.QRCodeDetector.empty();
      final (text, points, _) = detector.detectAndDecode(input);
      if (points.isNotEmpty) points.dispose();
      detector.dispose();
      if (text.isNotEmpty) return QrData.fromRaw(text);
    } catch (_) {}
    return null;
  }

  static bool _hasSquares(cv.Mat gray) {
    cv.Mat? binary;
    try {
      binary = cv.adaptiveThreshold(gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 31, 10);
      final (contours, hierarchy) = cv.findContours(binary, cv.RETR_TREE, cv.CHAIN_APPROX_SIMPLE);
      int markers = 0;
      for (int i = 0; i < contours.length; i++) {
        if (cv.contourArea(contours[i]) < 100) continue;
        if (hierarchy[i].val3 != -1 && hierarchy[hierarchy[i].val3].val3 != -1) markers++;
      }
      return markers >= 3;
    } catch (_) {
      return false;
    } finally {
      binary?.dispose();
    }
  }

  static QrData? searchBroad(cv.Mat warped) {
    return detectQr(warped, const Rect.fromLTRB(0.4, 0.0, 1.0, 0.4));
  }
}
