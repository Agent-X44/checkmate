import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';

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
  Standard50QuestionsTemplate()
      : super(
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

  /// Vertical calibration offset used during OMR processing.
  static const int calibratedYOffset = 0;

  /// Horizontal calibration offset used during OMR processing.
  static const int calibratedXOffset = 0;

  /// The normalized starting position for the bubble grid within an answer region.
  static const double defaultGridStart = 0.006;

  /// The normalized width of the bubble grid relative to the answer region.
  static const double defaultGridWidth = 1.000;

  /// The normalized vertical spacing between questions in the grid.
  static const double defaultGridYSpace = 0.006;

  /// The dark pixel percentage threshold (0.0 to 1.0) to consider a bubble "marked".
  static const double defaultThreshold = 0.156;

  /// The normalized height of an individual question strip for processing.
  static const double defaultStripHeight = 0.970;
}
