import 'package:flutter/material.dart';
import 'pdf_alignment.dart';

/// Defines the physical layout of a bubble sheet to allow for
/// dynamic cropping and processing without changing core algorithms.
class BubbleSheetTemplate {
  final String id;
  final String name;
  final String assetPath;

  /// Custom PDF overlay alignment for this specific template.
  final PdfAlignment pdfAlignment;

  /// Target aspect ratio of the paper (Width / Height).
  /// A4 is approximately 0.707.
  /// If set to 0, the processor will use the aspect ratio
  /// calculated from the detected physical corners of the paper
  /// instead of forcing a specific size.
  final double paperAspectRatio;

  /// Physical ratio between the printed marker centers, used to validate
  /// perspective geometry independently of the calibrated output image size.
  final double fiducialAspectRatio;

  /// Printed corner-circle diameter divided by the horizontal marker span.
  final double fiducialDiameterRatio;

  /// The normalized regions (0.0 to 1.0) where answers are located.
  /// Each Rect represents a column of questions.
  final List<Rect> answerRegions;

  /// The normalized region (0.0 to 1.0) where the QR code is located.
  final Rect? qrRegion;

  /// The normalized region (0.0 to 1.0) where the Set (A/B) checkboxes are located.
  final Rect? setRegion;

  /// Optional: Specific bubble coordinates for Set detection.
  final List<Offset>? setBubbles;

  final int totalQuestions;
  final int choicesPerQuestion;
  final int columns;
  final int mcqCount;
  final int tfCount;

  /// Optional exact bubble centres (question order, then choice; A-B for TF
  /// rows), normalized to the warped sheet. When present, every edition grades
  /// by sampling these points instead of the row/column grid.
  final List<Offset>? answerBubbles;

  /// Half the sampled square's side, as a fraction of the sheet width, and
  /// the ink ratio above which a bubble counts as marked. Used with
  /// [answerBubbles].
  final double bubbleRadius;
  final double fillThreshold;

  /// Grid settings for OMR processing
  final double gridStart;
  final double gridWidth;
  final int calibratedYOffset;

  /// Visual configuration for the sheet generator.
  final bool showColumnOutlines;
  final double columnSpacing;
  final double innerPadding;

  /// Width of the final warped paper image for processing.
  final int targetWidth;

  const BubbleSheetTemplate({
    this.id = 'custom',
    required this.name,
    this.assetPath = 'assets/50_questions.png',
    this.pdfAlignment = const PdfAlignment(),
    this.paperAspectRatio = 0.707,
    this.fiducialAspectRatio = 0.681,
    this.fiducialDiameterRatio = 0.063,
    required this.answerRegions,
    this.qrRegion,
    this.setRegion,
    this.setBubbles,
    required this.totalQuestions,
    required this.choicesPerQuestion,
    this.columns = 1,
    this.mcqCount = 0,
    this.tfCount = 0,
    this.answerBubbles,
    this.bubbleRadius = 0.005,
    this.fillThreshold = 0.18,
    this.gridStart = 0.050,
    this.gridWidth = 0.920,
    this.calibratedYOffset = 0,
    this.showColumnOutlines = true,
    this.columnSpacing = 0.05,
    this.innerPadding = 0.02,
    this.targetWidth = 1500,
  });

  /// Helper to check if the template expects a fixed paper ratio
  /// or if it should adapt to the image's perspective.
  bool get isAdaptableAspectRatio => paperAspectRatio <= 0;

  /// Returns the target height based on width and aspect ratio.
  int get targetHeight =>
      isAdaptableAspectRatio ? -1 : (targetWidth / paperAspectRatio).round();
}
