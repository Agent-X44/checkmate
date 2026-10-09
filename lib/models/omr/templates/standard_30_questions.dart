import 'package:flutter/material.dart';
import '../bubble_grid_anchors.dart';
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
          fiducialAspectRatio: 0.320,
          fiducialDiameterRatio: 0.090,
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
          answerBubbles: _answerBubbles(),
          bubbleRadius: 0.018380537654020722,
          fillThreshold: 0.3647299950348587,
          gridStart: 0.25,
          gridWidth: 0.65,
        );
}

/// Calibrated bubble centres for the printed 30-question sheet, placed with
/// the developer Grading Template Builder (9 October 2026). The four anchors
/// are the centres of Q1 A, Q1 D, Q30 A and Q30 D; the other 116 bubbles are
/// interpolated between them exactly as the builder exported them.
const standard30Anchors = ColumnAnchors(
  Offset(0.2319350055594574, 0.3204569749188875),
  Offset(0.9236124509889985, 0.320540928047723),
  Offset(0.230061431999063, 0.8971763409090624),
  Offset(0.9247357721793066, 0.8971344669768322),
);

List<Offset> _answerBubbles() => [
      for (var row = 0; row < 30; row++)
        for (var choice = 0; choice < 4; choice++)
          BubbleGridAnchors.centre(standard30Anchors, 30, row, 4, choice)
    ];
