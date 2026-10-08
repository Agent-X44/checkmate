import 'bubble_sheet_template.dart';
import 'templates/standard_50_questions.dart';
import 'templates/standard_30_questions.dart';
import 'templates/mixed_15mcq_15tf.dart';
import 'templates/mixed_25mcq_25tf.dart';
import 'templates/mixed_20mcq_30tf.dart';
import 'templates/mixed_30mcq_20tf.dart';

class AnswerSheetTemplateRegistry {
  static final List<BubbleSheetTemplate> all = [
    Standard50QuestionsTemplate(),
    Standard30QuestionsTemplate(),
    Mixed15Mcq15TfTemplate(),
    Mixed25Mcq25TfTemplate(),
    Mixed20Mcq30TfTemplate(),
    Mixed30Mcq20TfTemplate(),
  ];

  static BubbleSheetTemplate? byId(String id) {
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static BubbleSheetTemplate forConfiguration(int totalQuestions, int mcqCount, int tfCount) {
    // Exact match
    try {
      return all.firstWhere((t) => t.totalQuestions == totalQuestions && t.mcqCount == mcqCount && t.tfCount == tfCount);
    } catch (e) {
      return forQuestionCount(totalQuestions);
    }
  }

  static BubbleSheetTemplate forQuestionCount(int totalQuestions) {
    return all
        .where((template) => template.totalQuestions >= totalQuestions)
        .fold<BubbleSheetTemplate?>(null, (best, template) {
          if (best == null || template.totalQuestions < best.totalQuestions) {
            return template;
          }
          return best;
        }) ??
        all.reduce((a, b) => a.totalQuestions > b.totalQuestions ? a : b);
  }
}
