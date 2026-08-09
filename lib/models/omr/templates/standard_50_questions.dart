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
  /// 
  /// NOTE: Coordinates are now normalized relative to the centers of the 
  /// 4 corner markers (Marker-to-Marker reference frame).
  Standard50QuestionsTemplate()
      : super(
          name: 'Standard 50 Questions',
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
          targetWidth: 1500,
        );

  /// Vertical calibration offset used during OMR processing.
  static const int calibratedYOffset = 0;

  /// Horizontal calibration offset used during OMR processing.
  static const int calibratedXOffset = 0;

  /// The normalized starting position for the bubble grid within an answer region.
  static const double defaultGridStart = 0.050;

  /// The normalized width of the bubble grid relative to the answer region.
  static const double defaultGridWidth = 0.920;

  /// The normalized vertical spacing between questions in the grid.
  static const double defaultGridYSpace = 0.006;

  /// The dark pixel percentage threshold (0.0 to 1.0) to consider a bubble "marked".
  static const double defaultThreshold = 0.156;

  /// The normalized height of an individual question strip for processing.
  static const double defaultStripHeight = 0.970;
}
