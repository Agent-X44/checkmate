class BubbleResult {
  final String? answer;
  final double confidence;
  final bool isFilled;
  final List<String> multipleAnswers;
  final bool isAmbiguous;
  final bool? isCorrect; // Added to store grading status

  BubbleResult({
    this.answer,
    required this.confidence,
    this.isFilled = false,
    this.multipleAnswers = const [],
    bool isAmbiguous = false,
    bool? isCorrect,
  })  : isAmbiguous = isAmbiguous || multipleAnswers.length > 1,
        isCorrect =
            isAmbiguous || multipleAnswers.length > 1 ? false : isCorrect;

  Map<String, dynamic> toMap() {
    return {
      'answer': answer,
      'confidence': confidence,
      'isFilled': isFilled,
      'multipleAnswers': multipleAnswers,
      'isAmbiguous': isAmbiguous,
      'isCorrect': isCorrect,
    };
  }

  BubbleResult copyWith({
    String? answer,
    double? confidence,
    bool? isFilled,
    List<String>? multipleAnswers,
    bool? isAmbiguous,
    bool? isCorrect,
  }) {
    return BubbleResult(
      answer: answer ?? this.answer,
      confidence: confidence ?? this.confidence,
      isFilled: isFilled ?? this.isFilled,
      multipleAnswers: multipleAnswers ?? this.multipleAnswers,
      isAmbiguous: this.isAmbiguous || (isAmbiguous ?? false),
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }
}
