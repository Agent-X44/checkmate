import 'package:flutter/material.dart';
import '../bubble_sheet_template.dart';

/// Optimized template for the PyImageSearch 5-question sample.
/// Hardcoded with calibrated values from latest user testing (9:49 PM).
class PyImageSearch5Template extends BubbleSheetTemplate {
  PyImageSearch5Template() : super(
    name: 'PyImageSearch Sample (5 Questions)',
    paperAspectRatio: 0.0, // Auto-detect from corners
    
    // Final Calibrated Left Edge: 0.15 (Skipping question numbers perfectly)
    answerRegions: [const Rect.fromLTRB(0.15, 0.05, 1.0, 0.8)],
    
    totalQuestions: 5,
    choicesPerQuestion: 5,
    columns: 1,
    targetWidth: 1500,
  );

  /// Final Calibrated vertical offset (9:49 PM)
  static const int calibratedYOffset = 58;

  /// Final Calibrated grid parameters (9:49 PM)
  static const double defaultGridStart = 0.08;
  static const double defaultGridWidth = 0.83;
}
