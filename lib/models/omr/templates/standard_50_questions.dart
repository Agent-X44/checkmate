import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';

class Standard50QuestionsTemplate extends BubbleSheetTemplate {
  Standard50QuestionsTemplate() : super(
    name: 'Standard 50 Questions',
    paperAspectRatio: 0.707, // A4
    answerRegions: [
      const Rect.fromLTRB(0.117, 0.416, 0.455, 0.937), // Left Column Box
      const Rect.fromLTRB(0.625, 0.416, 0.961, 0.937), // Right Column Box
    ],
    qrRegion: const Rect.fromLTRB(0.729, 0.099, 0.885, 0.209),
    setRegion: const Rect.fromLTRB(0.128, 0.169, 0.286, 0.204),
    setBubbles: const [
      Offset(0.149, 0.187),
      Offset(0.240, 0.186),
    ],
    totalQuestions: 50,
    choicesPerQuestion: 4,
    columns: 2,
    targetWidth: 1500,
  );

  static const int calibratedYOffset = 0;
  static const int calibratedXOffset = 0;
  static const double defaultGridStart = 0.006;
  static const double defaultGridWidth = 1.000;
  static const double defaultGridYSpace = 0.006;
  static const double defaultThreshold = 0.156;
  static const double defaultStripHeight = 0.970;
}
