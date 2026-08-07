import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/omr/bubble_sheet_template.dart';

class PdfAlignment {
  final double nameTop;
  final double nameLeft;
  final double nameScale;
  final double qrTop;
  final double qrRight;
  final double qrSize;
  final double setATop;
  final double setALeft;

  const PdfAlignment({
    this.nameTop = 87.1,
    this.nameLeft = 145.0,
    this.nameScale = 1.2,
    this.qrTop = 33.0,
    this.qrRight = 65.4,
    this.qrSize = 118.4,
    this.setATop = 175,
    this.setALeft = 145,
  });
}

class PdfGenerator {
  static Future<void> generateAndPrint(
    BubbleSheetTemplate template, {
    PdfAlignment alignment = const PdfAlignment(),
    required List<String> studentNames,
  }) async {
    final pdf = pw.Document();

    final ByteData bytes = await rootBundle.load('assets/50_questions.png');
    final Uint8List list = bytes.buffer.asUint8List();
    final pw.MemoryImage image = pw.MemoryImage(list);

    for (int i = 0; i < studentNames.length; i++) {
      final String studentName = studentNames[i];
      final String sheetId = "CM50-A-${(i + 1).toString().padLeft(4, '0')}";

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(
              top: 35, left: 25, right: 25, bottom: 25),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                pw.Image(image, fit: pw.BoxFit.contain),

                // Overlay: Name and Labels
                pw.Positioned(
                  top: alignment.nameTop - 20,
                  left: alignment.nameLeft - 85,
                  child: pw.Transform.scale(
                    scale: alignment.nameScale,
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
                            _checkbox('A', isChecked: false),
                            pw.SizedBox(width: 20),
                            _checkbox('B', isChecked: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Overlay: QR Code and Sheet ID (Centered)
                pw.Positioned(
                  top: alignment.qrTop,
                  right: alignment.qrRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: alignment.qrSize,
                        height: alignment.qrSize,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data:
                              '$studentName, $sheetId, CS101, Midterm Exam, ${template.name}',
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${template.name}_Batch.pdf',
    );
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
