import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';
import '../pdf_alignment.dart';

class Mixed15Mcq15TfTemplate extends BubbleSheetTemplate {
  Mixed15Mcq15TfTemplate()
      : super(
          id: 'mixed_30_15mcq_15tf_v1',
          name: '15 MCQ + 15 T/F',
          assetPath: 'assets/30_questions.png', // Placeholder
          pdfAlignment: const PdfAlignment.for30Questions(),
          paperAspectRatio: 0.449, // 545.27 / 1214.39
          fiducialAspectRatio: 0.320,
          fiducialDiameterRatio: 0.090,
          answerRegions: [
            const Rect.fromLTRB(0.1, 0.25, 0.9, 0.95), // Placeholder
          ],
          qrRegion: const Rect.fromLTRB(0.68, 0.1, 0.94, 0.22),
          setRegion: const Rect.fromLTRB(0.05, 0.08, 0.25, 0.13),
          setBubbles: const [
            Offset(0.085, 0.105),
            Offset(0.195, 0.105),
          ],
          totalQuestions: 30,
          choicesPerQuestion: 4,
          columns: 1,
          mcqCount: 15,
          tfCount: 15,
          targetWidth: 1500,
        );
}
