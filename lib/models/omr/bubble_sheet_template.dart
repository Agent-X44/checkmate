import 'package:flutter/material.dart';

/// Defines the physical layout of a bubble sheet to allow for
/// dynamic cropping and processing without changing core algorithms.
class BubbleSheetTemplate {
  final String name;

  /// Target aspect ratio of the paper (Width / Height).
  /// A4 is approximately 0.707.
  /// If set to 0, the processor will use the aspect ratio
  /// calculated from the detected physical corners of the paper
  /// instead of forcing a specific size.
  final double paperAspectRatio;
  
  /// The normalized region (0.0 to 1.0) where answers are located.
  final Rect answerRegion;

  /// The normalized region (0.0 to 1.0) where the QR code is located.
  final Rect? qrRegion;
  
  final int totalQuestions;
  final int choicesPerQuestion;
  final int columns;
  
  /// Visual configuration for the sheet generator.
  final bool showColumnOutlines;
  final double columnSpacing;
  final double innerPadding;
  
  /// Width of the final warped paper image for processing.
  final int targetWidth;

  const BubbleSheetTemplate({
    required this.name,
    this.paperAspectRatio = 0.707,
    required this.answerRegion,
    this.qrRegion,
    required this.totalQuestions,
    required this.choicesPerQuestion,
    this.columns = 1,
    this.showColumnOutlines = true,
    this.columnSpacing = 0.05,
    this.innerPadding = 0.02,
    this.targetWidth = 1500,
  });

  /// Helper to check if the template expects a fixed paper ratio
  /// or if it should adapt to the image's perspective.
  bool get isAdaptableAspectRatio => paperAspectRatio <= 0;

  /// Returns the target height based on width and aspect ratio.
  int get targetHeight => isAdaptableAspectRatio ? -1 : (targetWidth / paperAspectRatio).round();
}
