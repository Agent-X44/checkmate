import 'dart:typed_data';
import 'dart:convert';
import 'bubble_result.dart';

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

  /// The detected Exam Set (A or B).
  final String? detectedSet;

  /// The name of the template used for processing.
  final String templateName;

  /// Stable base layout ID, retained even when a developer preset is renamed.
  final String? templateId;

  /// Capacity of the matched printed template, supplied by local processing.
  /// This distinguishes unused printed rows from an incomplete detection.
  final int? questionCapacity;

  final List<Map<String, dynamic>> questionDetails;

  ProcessedSheet({
    required this.warpedImage,
    required this.thresholdImage,
    required this.answerRegion,
    required this.questionImages,
    required this.results,
    this.qrData,
    this.detectedSet,
    required this.templateName,
    this.templateId,
    this.questionCapacity,
    this.questionDetails = const [],
  });

  ProcessedSheet copyWith({
    Uint8List? warpedImage,
    Uint8List? thresholdImage,
    Uint8List? answerRegion,
    List<Uint8List>? questionImages,
    List<BubbleResult>? results,
    QrData? qrData,
    String? detectedSet,
    String? templateName,
    String? templateId,
    int? questionCapacity,
    List<Map<String, dynamic>>? questionDetails,
  }) {
    return ProcessedSheet(
      warpedImage: warpedImage ?? this.warpedImage,
      thresholdImage: thresholdImage ?? this.thresholdImage,
      answerRegion: answerRegion ?? this.answerRegion,
      questionImages: questionImages ?? this.questionImages,
      results: results ?? this.results,
      qrData: qrData ?? this.qrData,
      detectedSet: detectedSet ?? this.detectedSet,
      templateName: templateName ?? this.templateName,
      templateId: templateId ?? this.templateId,
      questionCapacity: questionCapacity ?? this.questionCapacity,
      questionDetails: questionDetails ?? this.questionDetails,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'warpedImage': base64Encode(warpedImage),
      'thresholdImage': base64Encode(thresholdImage),
      'answerRegion': base64Encode(answerRegion),
      'questionImages': questionImages.map((img) => base64Encode(img)).toList(),
      'results': results.map((res) => res.toMap()).toList(),
      'questionDetails': questionDetails,
      'qrData': qrData?.toMap(),
      'detectedSet': detectedSet,
      'templateName': templateName,
      'templateId': templateId,
      'questionCapacity': questionCapacity,
    };
  }

  String toJson() => jsonEncode(toMap());

  /// Only JSON evaluation data is synchronized; raw images stay on the device.
  Map<String, dynamic> toSyncResult() => {
        'sheet_id': qrData?.sheetIdentifier ?? 'unknown',
        'score': results.where((result) => result.isCorrect == true).length,
        'total': results.length,
        'answers': [
          for (var index = 0; index < results.length; index++)
            {
              ...results[index].toMap(),
              'question_number': index + 1,
              if (index < questionDetails.length) ...{
                'question_id': questionDetails[index]['id'],
                'question_text': questionDetails[index]['question_text'] ??
                    questionDetails[index]['questionText'] ??
                    '',
                'question_type': questionDetails[index]['question_type'] ??
                    questionDetails[index]['questionType'] ??
                    'MCQ',
                'correct_answer': questionDetails[index]['correct_answer'] ??
                    questionDetails[index]['correctAnswer'],
                'topic_tag': questionDetails[index]['topic_tag'] ??
                    questionDetails[index]['topicTag'] ??
                    '',
                'options': questionDetails[index]['options'] is List
                    ? questionDetails[index]['options']
                    : <String>[],
              },
            },
        ],
      };
}
