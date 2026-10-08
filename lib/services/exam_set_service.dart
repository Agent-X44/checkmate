import 'dart:math';

class ExamSetService {
  /// Generates a reshuffled "Set B" based on the original questions (Set A).
  ///
  /// Takes a list of question maps (as fetched from the database).
  /// Returns a new list with each question type shuffled within its own part.
  static List<Map<String, dynamic>> generateSetB(List<Map<String, dynamic>> originalQuestions) {
    if (originalQuestions.isEmpty) return [];

    String typeOf(Map<String, dynamic> question) {
      final explicit = question['questionType'] ?? question['question_type'];
      if (explicit == 'TF' || explicit == 'MCQ') return explicit as String;
      return question['part'] == 2 ? 'TF' : 'MCQ';
    }

    final mcq = originalQuestions
        .where((q) => typeOf(q) == 'MCQ')
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
    final tf = originalQuestions
        .where((q) => typeOf(q) == 'TF')
        .map((q) => Map<String, dynamic>.from(q))
        .toList();

    // Keep the question-type sections stable for answer-sheet alignment.
    final random = Random(originalQuestions.length * 42);
    mcq.shuffle(random);
    tf.shuffle(random);
    return [...mcq, ...tf];
  }
}
