import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:checkmate/models/omr/bubble_sheet_template.dart';

/// Matches the PDF generator's printed QR dimensions and placement.
/// Renders QR modules deterministically with OpenCV drawing, without AI/OCR.
cv.Rect addPrintedSheetQr(cv.Mat artwork, BubbleSheetTemplate template,
    {String sheetId = 'CMTEST'}) {
  const pdfWidth = 545.27;
  final alignment = template.pdfAlignment;
  final scale = artwork.width / pdfWidth;
  final size = (alignment.qrSize * scale).round();
  final left =
      (artwork.width - (alignment.qrRight + alignment.qrSize) * scale).round();
  final top = (alignment.qrTop * scale).round();
  final qr = QrImage(
      QrCode.fromData(data: sheetId, errorCorrectLevel: QrErrorCorrectLevel.M));
  final modules = qr.moduleCount + 8;
  cv.rectangle(artwork, cv.Rect(left, top, size, size), cv.Scalar.all(255),
      thickness: -1);
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      final x = left + ((col + 4) * size / modules).round();
      final y = top + ((row + 4) * size / modules).round();
      final right = left + ((col + 5) * size / modules).round();
      final bottom = top + ((row + 5) * size / modules).round();
      cv.rectangle(
          artwork, cv.Rect(x, y, right - x, bottom - y), cv.Scalar.all(0),
          thickness: -1);
    }
  }
  final inset = (4 * size / modules).round();
  return cv.Rect(left + inset, top + inset, size - 2 * inset, size - 2 * inset);
}
