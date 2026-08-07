import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/omr/processed_sheet.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000', // Default Android Emulator address for localhost
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// Generates an exam based on a topic using Llama 3
  static Future<Map<String, dynamic>> generateExam(String topic, {int count = 5}) async {
    try {
      final response = await _dio.post('/generate-exam', data: {
        'topic': topic,
        'question_count': count,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (generateExam): $e");
      rethrow;
    }
  }

  /// Uploads OMR results for pedagogical analysis and storage
  static Future<Map<String, dynamic>> submitGradedSheet({
    required String studentId,
    required String courseId,
    required ProcessedSheet sheet,
  }) async {
    try {
      final results = sheet.results.map((res) => res.toMap()).toList();
      
      final response = await _dio.post('/save-grades', data: {
        'student_id': studentId,
        'course_id': courseId,
        'score': _calculateScore(sheet),
        'results': results,
      });

      // Also trigger analysis
      final analysis = await _dio.post('/analyze-results', data: {
        'student_id': studentId,
        'course_id': courseId,
        'score': _calculateScore(sheet),
        'results': results,
      });

      return {
        'save': response.data,
        'analysis': analysis.data,
      };
    } catch (e) {
      debugPrint("API Error (submitGradedSheet): $e");
      rethrow;
    }
  }

  static double _calculateScore(ProcessedSheet sheet) {
    if (sheet.results.isEmpty) return 0.0;
    int correct = sheet.results.where((r) => r.answer != null && !r.isAmbiguous).length;
    return (correct / sheet.results.length) * 100;
  }
}
