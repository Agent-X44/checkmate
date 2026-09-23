import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/pdf_alignment.dart';
export '../models/omr/pdf_alignment.dart';

class PdfGeneratorData {
  final Uint8List imageBytes;
  final String templateName;
  final PdfAlignment alignment;
  final List<Map<String, String>> sheetData;

  PdfGeneratorData({
    required this.imageBytes,
    required this.templateName,
    required this.alignment,
    required this.sheetData,
  });
}

class PdfGenerator {
  /// [LABEL: Future Architecture Model - Parallel PDF Generation]
  /// Spawns an isolate to process heavy PDF document creation, preventing UI stuttering
  /// when batch generating for hundreds of students.
  static Future<void> generateAndPrint(
    BubbleSheetTemplate template, {
    PdfAlignment? alignment,
    required List<Map<String, String>> sheetData,
  }) async {
    // 1. Load assets on Main Thread (rootBundle is not isolate-safe)
    final ByteData bytes = await rootBundle.load(template.assetPath);
    final Uint8List imageBytes = bytes.buffer.asUint8List();

    // 2. Prepare request data
    final request = PdfGeneratorData(
      imageBytes: imageBytes,
      templateName: template.name,
      alignment: alignment ?? template.pdfAlignment,
      sheetData: sheetData,
    );

    // 3. Heavy Compute offloaded to Background Isolate
    final pdfBytes = await compute(_generatePdfInternal, request);

    // 4. Print using Main Thread
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${template.name}_Batch.pdf',
    );
  }

  static Future<Uint8List> _generatePdfInternal(PdfGeneratorData data) async {
    final pdf = pw.Document();
    final pw.MemoryImage image = pw.MemoryImage(data.imageBytes);

    // Calculate exact page format based on image aspect ratio to prevent white space
    final double imgWidth = image.width?.toDouble() ?? 545.27;
    final double imgHeight = image.height?.toDouble() ?? 781.89;
    final double imgAspect = imgWidth / imgHeight;

    // Keep the base width similar to A4 to maintain text sizes and coordinate scale
    const double baseWidth = 545.27; // A4 width (595.27) minus 50 margin
    final double baseHeight = baseWidth / imgAspect;

    // Create a custom page format that tightly hugs the image with exactly 20px margin on all 4 corners
    final customFormat = PdfPageFormat(
      baseWidth + 40, // 20px left + 20px right
      baseHeight + 40, // 20px top + 20px bottom
      marginAll: 20,
    );

    for (int i = 0; i < data.sheetData.length; i++) {
      final String studentName = data.sheetData[i]['name'] ?? 'Unknown Student';
      final String sheetId = data.sheetData[i]['qrCode'] ?? 'UNKNOWN_ID';
      final String setType = data.sheetData[i]['set'] ?? 'A';

      pdf.addPage(
        pw.Page(
          pageFormat: customFormat,
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                pw.Image(image, fit: pw.BoxFit.fill),

                // Overlay: Name and Labels
                pw.Positioned(
                  top: data.alignment.nameTop - 20,
                  left: data.alignment.nameLeft - 85,
                  child: pw.Transform.scale(
                    scale: data.alignment.nameScale,
                    alignment: pw.Alignment.topLeft,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Text(
                              'Name: ',
                              style: const pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Container(
                              decoration: const pw.BoxDecoration(
                                border:
                                    pw.Border(bottom: pw.BorderSide(width: 1)),
                              ),
                              child: pw.Text(
                                studentName,
                                style: const pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 15),
                        pw.Row(
                          children: [
                            pw.Text(
                              'Set: ',
                              style: const pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            _checkbox('1', isChecked: setType == '1'),
                            pw.SizedBox(width: 20),
                            _checkbox('2', isChecked: setType == '2'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Overlay: QR Code and Sheet ID (Centered)
                pw.Positioned(
                  top: data.alignment.qrTop,
                  right: data.alignment.qrRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: data.alignment.qrSize,
                        height: data.alignment.qrSize,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: sheetId,
                          drawText: false,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Sheet ID: $sheetId',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  static pw.Widget _checkbox(String label, {bool isChecked = false}) {
    return pw.Row(
      children: [
        pw.Container(
          width: 15,
          height: 15,
          decoration: const pw.BoxDecoration(
              border: pw.Border(
            top: pw.BorderSide(width: 1),
            left: pw.BorderSide(width: 1),
            right: pw.BorderSide(width: 1),
            bottom: pw.BorderSide(width: 1),
          )),
          child: isChecked
              ? pw.Center(
                  child:
                      pw.Container(width: 8, height: 8, color: PdfColors.black))
              : null,
        ),
        pw.SizedBox(width: 5),
        pw.Text(label, style: const pw.TextStyle(fontSize: 14)),
      ],
    );
  }
}
