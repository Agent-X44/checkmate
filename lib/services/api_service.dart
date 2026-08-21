import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/omr/processed_sheet.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000',
      connectTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 2),
    ),
  );

  static Future<Map<String, dynamic>> resolveSheet(String identifier) async {
    try {
      final response = await _dio.get('/resolve-sheet/$identifier');
      return response.data;
    } catch (e) {
      debugPrint("API Error (resolveSheet): $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createExam({
    required String topic, 
    required String classId, 
    int questionCount = 5,
  }) async {
    try {
      final response = await _dio.post('/generate-exam', data: {
        'topic': topic,
        'class_id': classId,
        'question_count': questionCount,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (createExam): $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> batchSyncResults({
    required String examId,
    required List<Map<String, dynamic>> results,
  }) async {
    try {
      final response = await _dio.post('/batch-save-grades', data: {
        'exam_id': examId,
        'results': results,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (batchSyncResults): $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> analyzeClass(String examId) async {
    try {
      final response = await _dio.post('/analyze-class/$examId');
      return response.data;
    } catch (e) {
      debugPrint("API Error (analyzeClass): $e");
      rethrow;
    }
  }

  static Future<void> approveExam(String examId) async {
    try {
      await _dio.post('/approve-exam/$examId');
    } catch (e) {
      debugPrint("API Error (approveExam): $e");
      rethrow;
    }
  }

  static Future<void> releaseResults(String examId) async {
    try {
      await _dio.post('/release-results/$examId');
    } catch (e) {
      debugPrint("API Error (releaseResults): $e");
      rethrow;
    }
  }

  static Future<Uint8List> exportToDocx(String title, List<dynamic> questions) async {
    try {
      final response = await _dio.post(
        '/export-docx',
        data: {'title': title, 'questions': questions},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data);
    } catch (e) {
      debugPrint("API Error (exportToDocx): $e");
      rethrow;
    }
  }

  /// BR-02: Streaming version for live debugging logs.
  static Stream<String> generateExamStream({
    required String topic,
    required String classId,
    int questionCount = 5,
  }) async* {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('${_dio.options.baseUrl}/generate-exam-stream'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'topic': topic,
        'class_id': classId,
        'question_count': questionCount,
      }));
      
      final response = await request.close();
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isNotEmpty) yield line;
      }
    } catch (e) {
      yield "ERROR: $e";
    } finally {
      client.close();
    }
  }

  static double calculateScore(ProcessedSheet sheet) {
    if (sheet.results.isEmpty) return 0.0;
    int correct = sheet.results.where((r) => r.answer != null && !r.isAmbiguous).length;
    return (correct / sheet.results.length) * 100;
  }
}
