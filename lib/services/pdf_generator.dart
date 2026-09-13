import 'package:flutter/foundation.dart';
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
    this.nameTop = 115.8,
    this.nameLeft = 172.5,
    this.nameScale = 1.0,
    this.qrTop = 57.0,
    this.qrRight = 99.6,
    this.qrSize = 107.0,
    this.setATop = 175,
    this.setALeft = 145,
  });
}

class PdfGeneratorData {
  final Uint8List imageBytes;
  final String templateName;
  final PdfAlignment alignment;
  final List<String> studentNames;

  PdfGeneratorData({
    required this.imageBytes,
    required this.templateName,
    required this.alignment,
    required this.studentNames,
  });
}

class PdfGenerator {
  /// [LABEL: Future Architecture Model - Parallel PDF Generation]
  /// Spawns an isolate to process heavy PDF document creation, preventing UI stuttering
  /// when batch generating for hundreds of students.
  static Future<void> generateAndPrint(
    BubbleSheetTemplate template, {
    PdfAlignment alignment = const PdfAlignment(),
    required List<String> studentNames,
  }) async {
    // 1. Load assets on Main Thread (rootBundle is not isolate-safe)
    final ByteData bytes = await rootBundle.load('assets/50_questions.png');
    final Uint8List imageBytes = bytes.buffer.asUint8List();

    // 2. Prepare request data
    final request = PdfGeneratorData(
      imageBytes: imageBytes,
      templateName: template.name,
      alignment: alignment,
      studentNames: studentNames,
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

    for (int i = 0; i < data.studentNames.length; i++) {
      final String studentName = data.studentNames[i];
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
