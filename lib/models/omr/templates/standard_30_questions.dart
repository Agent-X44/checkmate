import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';
import '../pdf_alignment.dart';

class Standard30QuestionsTemplate extends BubbleSheetTemplate {
  Standard30QuestionsTemplate()
      : super(
          id: 'standard_30_questions',
          name: 'Standard 30 Questions',
          assetPath: 'assets/30_questions.png',
          pdfAlignment: const PdfAlignment.for30Questions(),
          paperAspectRatio: 0.449, // 545.27 / 1214.39
          answerRegions: [
            const Rect.fromLTRB(0.134, 0.314, 0.990, 0.908),
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
          mcqCount: 30,
          tfCount: 0,
          targetWidth: 1500,
          gridStart: 0.25,
          gridWidth: 0.65,
        );
}
