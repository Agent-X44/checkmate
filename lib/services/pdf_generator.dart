import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/omr/bubble_sheet_template.dart';

class PdfAlignment {
  final double nameTop;
  final double nameLeft;
  final double qrTop;
  final double qrRight;
  final double setATop;
  final double setALeft;

  const PdfAlignment({
    this.nameTop = 131,
    this.nameLeft = 145,
    this.qrTop = 96,
    this.qrRight = 62,
    this.setATop = 175,
    this.setALeft = 145,
  });
}

class PdfGenerator {
  static Future<void> generateAndPrint(
    BubbleSheetTemplate template, {
    PdfAlignment alignment = const PdfAlignment(),
  }) async {
    final pdf = pw.Document();

    final ByteData bytes = await rootBundle.load('assets/50_questions.png');
    final Uint8List list = bytes.buffer.asUint8List();
    final pw.MemoryImage image = pw.MemoryImage(list);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 35, left: 25, right: 25, bottom: 25),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Image(image, fit: pw.BoxFit.contain),

              // Overlay: Name and Labels
              pw.Positioned(
                top: alignment.nameTop - 20,
                left: alignment.nameLeft - 85,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          'Name: ',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Container(
                          width: 250,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 1)),
                          ),
                          child: pw.Text(
                            'JOHN DOE',
                            style: pw.TextStyle(
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
                          style: pw.TextStyle(
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

              // Overlay: QR Code and Sheet ID (Centered)
              pw.Positioned(
                top: alignment.qrTop,
                right: alignment.qrRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 75,
                      height: 75,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: 'JOHN DOE, CM50-A-0001, CS101, Midterm Exam',
                        drawText: false,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Sheet ID: CM50-A-0001',
                      style: pw.TextStyle(
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${template.name}.pdf',
    );
  }

  static pw.Widget _checkbox(String label, {bool isChecked = false}) {
    return pw.Row(
      children: [
        pw.Container(
          width: 15,
          height: 15,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: isChecked
              ? pw.Center(child: pw.Container(width: 8, height: 8, color: PdfColors.black))
              : null,
        ),
        pw.SizedBox(width: 5),
        pw.Text(label, style: const pw.TextStyle(fontSize: 14)),
      ],
    );
  }
}
