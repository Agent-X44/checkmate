import 'dart:convert';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/omr/processed_sheet.dart';

/// Service for interacting with the FastAPI Backend for AI and OMR metadata.
///
/// Enforces:
/// - BR-02: MCQ/TF Quiz support
/// - BR-03: Instructor validation/approval of exams
/// - BR-05: Sheet resolution (Metadata to Student ID)
/// - BR-07: Batch sync to backend
/// - BR-08: Persistence before analysis
/// - BR-09: Class-wide pedagogical insights (AI)
/// - BR-10: Personalized student recommendations (AI)
/// - BR-11: Controlled release of results
/// - BR-13: Export formats (DOCX/PDF)
class ApiService {
  // Hugging Face Space URL for CheckMate-Backend
  static const String hfSpaceUrl = 'https://noelpi-checkmate-backend.hf.space';
  static const String localUrl = 'http://10.0.2.2:8000';

  static final dio.Dio _dio = dio.Dio(
    dio.BaseOptions(
      // Prefer the Hugging Face backend for the project demo, but keep the local FastAPI route as a fallback.
      baseUrl: hfSpaceUrl,
      connectTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 2),
    ),
  );

  /// Configures custom backend URL dynamically (e.g. for local testing vs cloud)
  static void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  static String get baseUrl => _dio.options.baseUrl;

  static bool _isValidUuid(String value) {
    if (value.trim().isEmpty) return false;
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value.trim());
  }

  static Future<Map<String, dynamic>> resolveSheet(String identifier) async {
    if (!_isValidUuid(identifier)) {
      throw const FormatException('Invalid sheet ID format.');
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      final headers = session != null
          ? {'Authorization': 'Bearer ${session.accessToken}'}
          : null;

      final response = await _dio.get(
        '/resolve-sheet/$identifier',
        options: dio.Options(headers: headers),
      );
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
    String assessmentType = 'Quiz',
  }) async {
    if (!_isValidUuid(classId)) {
      throw const FormatException('Invalid class ID format.');
    }

    try {
      final response = await _dio.post('/generate-exam', data: {
        'topic': topic,
        'class_id': classId,
        'question_count': questionCount,
        'assessment_type': assessmentType,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (createExam): $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> saveDraft({
    required String classId,
    required String title,
    required String assessmentType,
    required List<dynamic> questions,
    bool hasMultipleSets = false,
  }) async {
    try {
      final response = await _dio.post('/save-draft', data: {
        'class_id': classId,
        'title': title,
        'assessment_type': assessmentType,
        'questions': questions,
        'has_multiple_sets': hasMultipleSets,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (saveDraft): $e");
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
      debugPrint(
          "API Error (batchSyncResults): $e. Using direct Supabase fallback...");
      for (final r in results) {
        final sheetId = r['sheet_id']?.toString() ?? '';
        final score = (r['score'] as num?)?.toInt() ?? 0;
        final total = (r['total'] as num?)?.toInt() ?? 0;
        final pct = total > 0 ? (score / total * 100) : 0.0;

        if (sheetId.isNotEmpty && sheetId != 'unknown') {
          try {
            await Supabase.instance.client.from('grades').upsert({
              'sheet_id': sheetId,
              'score': score,
              'total_questions': total,
              'percentage': pct,
            });
          } catch (dbErr) {
            debugPrint("Direct grade upsert error for sheet $sheetId: $dbErr");
          }
        }
      }
      return {'status': 'success'};
    }
  }

  static Future<Map<String, dynamic>> analyzeClass(String examId) async {
    try {
      final response = await _dio.post('/analyze-class', data: {
        'exam_id': examId,
        'class_id': '',
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (analyzeClass): $e");
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getStudentInsight({
    required String studentName,
    required int score,
    required int total,
    List<dynamic> errors = const [],
  }) async {
    try {
      final response = await _dio.post('/student-insight', data: {
        'student_name': studentName,
        'score': score,
        'total': total,
        'errors': errors,
      });
      return response.data;
    } catch (e) {
      debugPrint("API Error (getStudentInsight): $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getExamQuestions(
      String examId) async {
    try {
      final response = await _dio.get('/get-exam-questions/$examId');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      debugPrint("API Error (getExamQuestions): $e");
      rethrow;
    }
  }

  static Future<void> updateQuestion({
    required String questionId,
    required String questionText,
    required List<String> options,
    required String correctAnswer,
  }) async {
    try {
      await _dio.put('/update-question/$questionId', data: {
        'question_text': questionText,
        'options': options,
        'correct_answer': correctAnswer,
      });
    } catch (e) {
      debugPrint("API Error (updateQuestion): $e");
      rethrow;
    }
  }

  static Future<void> deleteExamApi(String examId) async {
    try {
      await _dio.delete('/delete-exam/$examId');
    } catch (e) {
      debugPrint("API Error (deleteExamApi): $e");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getExams(String classId) async {
    try {
      final response = await _dio.get('/get-exams/$classId');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      debugPrint("API Error (getExams): $e");
      rethrow;
    }
  }

  static Future<void> deleteCourse(String classId) async {
    try {
      await _dio.delete('/delete-course/$classId');
    } catch (e) {
      debugPrint("API Error (deleteCourse): $e");
      rethrow;
    }
  }

  static Future<void> approveExam(String examId) async {
    try {
      await _dio.post('/approve-exam/$examId');
    } catch (e) {
      debugPrint(
          "API Error (approveExam): $e. Using direct Supabase fallback...");
      await Supabase.instance.client
          .from('exams')
          .update({'is_approved': true, 'status': 'Ready'}).eq('id', examId);
    }
  }

  static Future<void> unapproveExam(String examId) async {
    try {
      await _dio.post('/unapprove-exam/$examId');
    } catch (e) {
      debugPrint(
          "API Error (unapproveExam): $e. Using direct Supabase fallback...");
      await Supabase.instance.client
          .from('exams')
          .update({'is_approved': false, 'status': 'Draft'}).eq('id', examId);
    }
  }

  static Future<void> releaseResults(String examId) async {
    try {
      await _dio.post('/release-results/$examId');
    } catch (e) {
      debugPrint(
          "API Error (releaseResults): $e. Using direct Supabase fallback...");
      await Supabase.instance.client.from('exams').update(
          {'results_released': true, 'status': 'Published'}).eq('id', examId);
    }
  }

  static Future<Uint8List> exportToDocx(
      String title, List<dynamic> questions) async {
    try {
      final response = await _dio.post(
        '/export-docx',
        data: {'title': title, 'questions': questions},
        options: dio.Options(responseType: dio.ResponseType.bytes),
      );
      return Uint8List.fromList(response.data);
    } catch (e) {
      debugPrint("API Error (exportToDocx): $e");
      rethrow;
    }
  }

  /// BR-02: Streaming version for live debugging logs.
  /// BR-02: Streaming version that yields tokens and final structured questions.
  static Stream<Map<String, dynamic>> generateExamStream({
    required String topic,
    required String classId,
    int questionCount = 5,
    String assessmentType = 'Quiz',
    bool includeMcq = true,
    bool includeTf = true,
    int mcqCount = 5,
    int tfCount = 0,
    String sourceMode = 'topic',
    bool hasMultipleSets = false,
  }) async* {
    try {
      final formData = dio.FormData.fromMap({
        'topic': topic,
        'class_id': classId,
        'question_count': questionCount,
        'assessment_type': assessmentType,
        'include_mcq': includeMcq,
        'include_tf': includeTf,
        'mcq_count': mcqCount,
        'tf_count': tfCount,
        'source_mode': sourceMode,
        'has_multiple_sets': hasMultipleSets,
      });
      final response = await _dio.post(
        '/generate-exam-stream',
        data: formData,
        options: dio.Options(responseType: dio.ResponseType.stream),
      );
      final byteStream = (response.data as dio.ResponseBody).stream;
      await for (final line
          in utf8.decoder.bind(byteStream).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          try {
            final jsonStr = line.substring(6).trim();
            final Map<String, dynamic> data = jsonDecode(jsonStr);
            yield data;
          } catch (_) {}
        }
      }
    } catch (e) {
      yield {'type': 'error', 'content': e.toString()};
    }
  }

  /// BR-02: Multipart upload variant that streams the same server-sent events while sending a file.
  static Stream<Map<String, dynamic>> generateExamWithFile({
    required String topic,
    required String classId,
    required List<int> fileBytes,
    required String filename,
    int questionCount = 5,
    String assessmentType = 'Quiz',
    bool includeMcq = true,
    bool includeTf = true,
    int mcqCount = 5,
    int tfCount = 0,
    String sourceMode = 'material',
    bool hasMultipleSets = false,
  }) async* {
    try {
      final formData = dio.FormData.fromMap({
        'topic': topic,
        'class_id': classId,
        'question_count': questionCount,
        'assessment_type': assessmentType,
        'include_mcq': includeMcq,
        'include_tf': includeTf,
        'mcq_count': mcqCount,
        'tf_count': tfCount,
        'source_mode': sourceMode,
        'has_multiple_sets': hasMultipleSets,
        'file': dio.MultipartFile.fromBytes(
          fileBytes,
          filename: filename,
          contentType: MediaType('application', 'octet-stream'),
        ),
      });

      final response = await _dio.post(
        '/generate-exam-stream',
        data: formData,
        options: dio.Options(
            responseType: dio.ResponseType.stream,
            headers: {'Content-Type': 'multipart/form-data'}),
      );

      // Dio wraps streamed responses in ResponseBody.
      final Stream<List<int>> byteStream =
          (response.data as dio.ResponseBody).stream;
      await for (final line in utf8.decoder
          .bind(byteStream.cast<List<int>>())
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          try {
            final jsonStr = line.substring(6).trim();
            final Map<String, dynamic> data = jsonDecode(jsonStr);
            yield data;
          } catch (_) {}
        }
      }
    } catch (e) {
      yield {'type': 'error', 'content': e.toString()};
    }
  }

  static double calculateScore(ProcessedSheet sheet) {
    if (sheet.results.isEmpty) return 0.0;
    int correct = sheet.results.where((r) => r.isCorrect == true).length;
    return (correct / sheet.results.length) * 100;
  }
}
