import 'dart:convert';
import 'dart:io';

import 'package:checkmate/services/pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('30-question sheets use two A4 slots and keep an odd final sheet',
      () async {
    final imageBytes = await File('assets/30_questions.png').readAsBytes();
    final pdfBytes = await PdfGenerator.generatePdfBytes(PdfGeneratorData(
      imageBytes: imageBytes,
      templateId: 'standard_30_questions',
      templateName: 'Standard 30 Questions',
      alignment: const PdfAlignment.for30Questions(),
      sheetData: const [
        {'name': 'Student One', 'qrCode': 'CM-ABCDEFGH'},
        {'name': 'Student Two', 'qrCode': 'CM-JKLMNPQR'},
        {'name': 'Student Three', 'qrCode': 'CM-STUVWXYZ'},
      ],
    ));

    final pdf = latin1.decode(pdfBytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length, 2);
  });
}
