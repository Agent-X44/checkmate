import 'dart:typed_data';
import '../../services/cv/bubble_detection_service.dart';

/// The output of the OMR preprocessing pipeline.
/// Contains images and detected answers.
class ProcessedSheet {
  /// The high-res paper image after perspective correction.
  final Uint8List warpedImage;
  
  /// The binary (black and white) image of the entire paper.
  final Uint8List thresholdImage;
  
  /// The specific cropped region containing only the bubbles.
  final Uint8List answerRegion;
  
  /// A list of individual crops, each containing exactly one question row.
  final List<Uint8List> questionImages;

  /// The graded results for each question.
  final List<BubbleResult> results;

  ProcessedSheet({
    required this.warpedImage,
    required this.thresholdImage,
    required this.answerRegion,
    required this.questionImages,
    required this.results,
  });
}
