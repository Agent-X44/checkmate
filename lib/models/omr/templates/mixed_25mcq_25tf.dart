import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';
import '../pdf_alignment.dart';

class Mixed25Mcq25TfTemplate extends BubbleSheetTemplate {
  Mixed25Mcq25TfTemplate()
      : super(
          id: 'mixed_50_25mcq_25tf_v1',
          name: '25 MCQ + 25 T/F',
          assetPath: 'assets/50_questions.png', // Placeholder
          pdfAlignment: const PdfAlignment.for50Questions(),
          paperAspectRatio: 0.707,
          answerRegions: [
            const Rect.fromLTRB(0.044, 0.350, 0.446, 0.940), // Left Column Box (Placeholder)
            const Rect.fromLTRB(0.648, 0.350, 0.980, 0.940), // Right Column Box (Placeholder)
          ],
          qrRegion: const Rect.fromLTRB(0.750, 0.005, 0.960, 0.150),
          setRegion: const Rect.fromLTRB(0.050, 0.080, 0.250, 0.130),
          setBubbles: const [
            Offset(0.085, 0.105),
            Offset(0.195, 0.105),
          ],
          totalQuestions: 50,
          choicesPerQuestion: 4, // Max choices across all questions
          columns: 2,
          mcqCount: 25,
          tfCount: 25,
          targetWidth: 1500,
        );
}
