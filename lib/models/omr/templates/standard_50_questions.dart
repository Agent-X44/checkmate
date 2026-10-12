import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';
import '../pdf_alignment.dart';

/// A template definition for a standard 50-question multiple-choice bubble sheet.
///
/// This template follows a two-column layout optimized for A4 paper aspect ratio (0.707).
/// It includes regions for answer bubbles, a QR code for sheet identification,
/// and a "Set" region for detecting exam versions (e.g., Set A or B).
///
/// All [Rect] and [Offset] values are normalized (0.0 to 1.0) relative to the
/// dimensions of the warped paper image.
class Standard50QuestionsTemplate extends BubbleSheetTemplate {
  /// Creates a new instance of the [Standard50QuestionsTemplate].
  ///
  /// The template is pre-configured with:
  /// * 50 total questions across 2 columns.
  /// * 4 choices per question.
  /// * A target width of 1500 pixels for OMR processing.
  /// 
  /// NOTE: Coordinates are now normalized relative to the centers of the 
  /// 4 corner markers (Marker-to-Marker reference frame).
  Standard50QuestionsTemplate()
      : super(
          id: 'standard_50_v1',
          name: 'Standard 50 Questions',
          assetPath: 'assets/50_questions.png',
          pdfAlignment: const PdfAlignment.for50Questions(),
          paperAspectRatio: 0.707, // A4
          answerRegions: [
            const Rect.fromLTRB(0.044, 0.350, 0.446, 0.940), // Left Column Box
            const Rect.fromLTRB(0.648, 0.350, 0.980, 0.940), // Right Column Box
          ],
          qrRegion: const Rect.fromLTRB(0.750, 0.005, 0.960, 0.150),
          setRegion: const Rect.fromLTRB(0.050, 0.080, 0.250, 0.130),
          setBubbles: const [
            Offset(0.085, 0.105),
            Offset(0.195, 0.105),
          ],
          totalQuestions: 50,
          choicesPerQuestion: 4,
          columns: 2,
          mcqCount: 50,
          tfCount: 0,
          targetWidth: 1500,
          calibratedYOffset: 0,
          gridStart: 0.050,
          gridWidth: 0.920,
          answerBubbles: _answerBubbles(),
          bubbleRadius: 9.3 / _markerFrameWidth,
          fillThreshold: 0.45,
        );

  /// Horizontal calibration offset used during OMR processing.
  static const int calibratedXOffset = 0;

  /// The normalized vertical spacing between questions in the grid.
  static const double defaultGridYSpace = 0.006;

  /// The dark pixel percentage threshold (0.0 to 1.0) to consider a bubble "marked".
  static const double defaultThreshold = 0.156;

  /// The normalized height of an individual question strip for processing.
  static const double defaultStripHeight = 0.970;
}

// Bubble centres measured from the printed ring outlines in
// assets/50_questions.png (pixels), normalized to its marker frame. Row
// spacing narrows from about 30 px at the top to 24 px at the bottom, so a
// linear grid between the first and last rows drifts by most of a bubble.
const _markerLeft = 49.5, _markerTop = 49.5;
const _markerFrameWidth = 1000.5 - _markerLeft;
const _markerFrameHeight = 1446.5 - _markerTop;

/// A-D centres of the left (Q1-25) and right (Q26-50) columns.
const _columnX = [
  [196.5, 280.5, 364.5, 449.0],
  [674.5, 759.0, 844.5, 929.5],
];

/// Shared by both columns.
const _rowY = [
  621.5, 651.0, 680.5, 710.0, 739.5, 768.5, 797.5, 825.5, 854.0, 882.5, //
  910.5, 938.5, 966.5, 994.5, 1023.5, 1051.5, 1079.5, 1107.25, 1135.5, //
  1162.5, 1189.5, 1216.5, 1242.5, 1269.5, 1293.5,
];

List<Offset> _answerBubbles() => [
      for (final column in _columnX)
        for (final y in _rowY)
          for (final x in column)
            Offset((x - _markerLeft) / _markerFrameWidth,
                (y - _markerTop) / _markerFrameHeight)
    ];
