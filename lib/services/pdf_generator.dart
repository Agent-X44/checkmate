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
  final String templateId;
  final String templateName;
  final PdfAlignment alignment;
  final List<Map<String, String>> sheetData;
  final bool hasMultipleSets;

  PdfGeneratorData({
    required this.imageBytes,
    required this.templateId,
    required this.templateName,
    required this.alignment,
    required this.sheetData,
    this.hasMultipleSets = false,
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
    bool hasMultipleSets = false,
  }) async {
    // 1. Load assets on Main Thread (rootBundle is not isolate-safe)
    final ByteData bytes = await rootBundle.load(template.assetPath);
    final Uint8List imageBytes = bytes.buffer.asUint8List();

    // 2. Prepare request data
    final request = PdfGeneratorData(
      imageBytes: imageBytes,
      templateId: template.id,
      templateName: template.name,
      alignment: alignment ?? template.pdfAlignment,
      sheetData: sheetData,
      hasMultipleSets: hasMultipleSets,
    );

    // 3. Heavy Compute offloaded to Background Isolate
    final pdfBytes = await compute(generatePdfBytes, request);

    // 4. Print using Main Thread
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${template.name}_Batch.pdf',
    );
  }

  static Future<Uint8List> generatePdfBytes(PdfGeneratorData data) async {
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

    if (data.templateId == 'standard_30_questions') {
      // The narrow 30-question artwork fits twice across portrait A4. Keep its
      // aspect ratio so OMR bubble coordinates and corner markers stay aligned.
      const gutter = 10.0;
      const outerMargin = 10.0;
      final sheetWidth =
          (PdfPageFormat.a4.width - outerMargin * 2 - gutter) / 2;
      final sheetHeight = sheetWidth / imgAspect;
      final top = (PdfPageFormat.a4.height - sheetHeight) / 2;
      final scale = sheetWidth / baseWidth;
      if (top < 0) {
        throw StateError('The 30-question artwork does not fit on A4.');
      }

      for (var i = 0; i < data.sheetData.length; i += 2) {
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Stack(children: [
            pw.Positioned(
              left: outerMargin,
              top: top,
              child: _buildSheet(data, image, data.sheetData[i], sheetWidth,
                  sheetHeight, scale),
            ),
            if (i + 1 < data.sheetData.length)
              pw.Positioned(
                left: outerMargin + sheetWidth + gutter,
                top: top,
                child: _buildSheet(data, image, data.sheetData[i + 1],
                    sheetWidth, sheetHeight, scale),
              ),
            pw.Positioned(
              left: PdfPageFormat.a4.width / 2 - 0.25,
              top: 8,
              child: pw.Container(
                width: 0.5,
                height: PdfPageFormat.a4.height - 16,
                color: PdfColors.grey400,
              ),
            ),
          ]),
        ));
      }
    } else {
      for (final sheet in data.sheetData) {
        pdf.addPage(pw.Page(
          pageFormat: customFormat,
          build: (context) =>
              _buildSheet(data, image, sheet, baseWidth, baseHeight, 1),
        ));
      }
    }

    return await pdf.save();
  }

  static pw.Widget _buildSheet(
    PdfGeneratorData data,
    pw.MemoryImage image,
    Map<String, String> sheet,
    double width,
    double height,
    double scale,
  ) {
    final studentName = sheet['name'] ?? 'Unknown Student';
    final sheetId = sheet['qrCode'] ?? 'UNKNOWN_ID';
    final setType = sheet['set'] ?? 'A';

    return pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(
        children: [
          pw.Image(image, width: width, height: height, fit: pw.BoxFit.fill),

          // Overlay: Name and Labels
          if (data.hasMultipleSets)
            pw.Positioned(
              top: (data.alignment.nameTop - 20) * scale,
              left: (data.alignment.nameLeft - 85) * scale,
              child: pw.Transform.scale(
                scale: data.alignment.nameScale * scale,
                alignment: pw.Alignment.topLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _nameRow(studentName, 1),
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
                        _checkbox('1',
                            isChecked: setType == '1' || setType == 'A'),
                        pw.SizedBox(width: 20),
                        _checkbox('2',
                            isChecked: setType == '2' || setType == 'B'),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            pw.Positioned(
              top: (data.alignment.nameTop - 20) * scale,
              left: 12 * scale,
              right:
                  (data.alignment.qrRight + data.alignment.qrSize + 12) * scale,
              child: pw.RichText(
                textAlign: pw.TextAlign.center,
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'Name: ',
                    style: pw.TextStyle(
                      fontSize: 14 * data.alignment.nameScale * scale,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: studentName,
                    style: pw.TextStyle(
                      fontSize: 16 * data.alignment.nameScale * scale,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ]),
              ),
            ),

          // Overlay: QR Code and Sheet ID (Centered)
          pw.Positioned(
            top: data.alignment.qrTop * scale,
            right: data.alignment.qrRight * scale,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: data.alignment.qrSize * scale,
                  height: data.alignment.qrSize * scale,
                  color: PdfColors.white,
                  padding: pw.EdgeInsets.all(3 * scale),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(
                      errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
                    ),
                    data: sheetId,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 5 * scale),
                pw.Text(
                  'Sheet ID: $sheetId',
                  style: pw.TextStyle(
                    fontSize: 9 * scale,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _nameRow(String studentName, double fontScale) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          'Name: ',
          style: pw.TextStyle(
            fontSize: 14 * fontScale,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          child: pw.Text(
            studentName,
            style: pw.TextStyle(
              fontSize: 16 * fontScale,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
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
