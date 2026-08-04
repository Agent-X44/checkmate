import 'dart:typed_data';
import 'dart:convert';
import '../../services/cv/bubble_detection_service.dart';

import 'qr_data.dart';

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

  /// The data decoded from the QR code on the sheet.
  final QrData? qrData;

  ProcessedSheet({
    required this.warpedImage,
    required this.thresholdImage,
    required this.answerRegion,
    required this.questionImages,
    required this.results,
    this.qrData,
  });

  Map<String, dynamic> toMap() {
    return {
      'warpedImage': base64Encode(warpedImage),
      'thresholdImage': base64Encode(thresholdImage),
      'answerRegion': base64Encode(answerRegion),
      'questionImages': questionImages.map((img) => base64Encode(img)).toList(),
      'results': results.map((res) => res.toMap()).toList(),
      'qrData': qrData?.toMap(),
    };
  }

  String toJson() => jsonEncode(toMap());
}
