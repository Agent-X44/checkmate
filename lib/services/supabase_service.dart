import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/course.dart';
import 'api_service.dart';

/// Service responsible for Supabase Authentication and Database interactions.
///
/// Enforces:
/// - BR-01: Course/Class Management (Create/Join)
/// - BR-12: Security & Row Level Security (Privacy)
class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;
  static SupabaseClient get client => _client;

  // --- AUTHENTICATION ---

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Google Sign-In Implementation (Android Optimized)
  static Future<AuthResponse?> signInWithGoogle() async {
    try {
      debugPrint("GOOGLE_AUTH: Starting flow...");

      // The Web Client ID (serverClientId) is the ONLY one needed for the handshake.
      const webClientId =
          '521288904900-cjt4oidq41d7er31gev8tddsfsc30s5q.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );

      // Sign out first to ensure the account picker always appears
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint("GOOGLE_AUTH: Cancelled.");
        return null;
      }

      debugPrint("GOOGLE_AUTH: User picked account: ${googleUser.email}");
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        debugPrint(
            "GOOGLE_AUTH: ERROR - idToken is null. Check Web Client ID configuration.");
        return null;
      }

      debugPrint("GOOGLE_AUTH: Synchronizing with Supabase...");
      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } catch (e) {
      debugPrint("GOOGLE_AUTH: CRITICAL FAIL - $e");
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // --- USER DATA ---

  static User? get currentUser => _client.auth.currentUser;

  static Session? get currentSession => _client.auth.currentSession;

  static Future<void> updateProfileName(String newName) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    // Update in profiles table
    await _client.from('profiles').upsert({
      'id': user.id,
      'name': newName,
      'email': user.email ?? '', // keep email
    });

    // Update in Auth user metadata so UI updates immediately
    await _client.auth.updateUser(UserAttributes(data: {'name': newName}));
  }

  // --- DATABASE: COURSES (BR-01) ---

  static Future<Course> createClass({
    required String name,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    final code = generateJoinCode();

    // Self-healing: Ensure profile exists before creating class (BR-01)
    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'name':
            user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? 'User',
        'email': user.email ?? '',
        'role': 'Instructor',
      });
    } catch (e) {
      debugPrint("Profile synchronization error: $e");
    }

    final response = await _client
        .from('classes')
        .insert({
          'name': name,
          'code': code,
          'instructor_id': user.id,
        })
        .select('*, profiles(*)')
        .single();

    return Course.fromMap(response, isOwner: true);
  }

  static Future<String> resetCourseCode(String classId) async {
    final newCode = generateJoinCode();
    await _client.from('classes').update({'code': newCode}).eq('id', classId);
    return newCode;
  }

  static Future<void> renameClass(String classId, String newName) async {
    await _client.from('classes').update({'name': newName}).eq('id', classId);
  }

  static Future<void> deleteClass(String classId) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    try {
      // 1. Try direct cascade delete via Supabase client
      // First, get all exams for this class
      final examRes =
          await _client.from('exams').select('id').eq('class_id', classId);
      final examIds = (examRes as List).map((e) => e['id'].toString()).toList();

      for (final examId in examIds) {
        try {
          await _client.from('ai_insights').delete().eq('exam_id', examId);
        } catch (_) {}

        try {
          final sheetRes = await _client
              .from('answer_sheets')
              .select('id')
              .eq('exam_id', examId);
          final sheetIds =
              (sheetRes as List).map((s) => s['id'].toString()).toList();
          for (final sheetId in sheetIds) {
            try {
              await _client.from('grades').delete().eq('sheet_id', sheetId);
            } catch (_) {}
          }
          await _client.from('answer_sheets').delete().eq('exam_id', examId);
        } catch (_) {}

        try {
          await _client.from('questions').delete().eq('exam_id', examId);
        } catch (_) {}
      }

      try {
        await _client.from('exams').delete().eq('class_id', classId);
      } catch (_) {}
      try {
        await _client.from('enrollments').delete().eq('class_id', classId);
      } catch (_) {}
      try {
        await _client
            .from('learning_materials')
            .delete()
            .eq('class_id', classId);
      } catch (_) {}

      // Finally delete class
      await _client.from('classes').delete().eq('id', classId);
    } catch (e) {
      debugPrint(
          "Direct Supabase course deletion notice ($e) - falling back to Backend API...");
      // Fallback to FastAPI backend endpoint which bypasses RLS and foreign keys
      await ApiService.deleteCourse(classId);
    }
  }

  static Future<void> unenrollClass(String classId) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");
    await _client
        .from('enrollments')
        .delete()
        .eq('user_id', user.id)
        .eq('class_id', classId);
  }

  static String normalizeJoinCode(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim().toUpperCase();
  }

  static Future<Map<String, dynamic>?> getCourseDataByCode(
      String classCode) async {
    final cleanCode = normalizeJoinCode(classCode);
    return await _client
        .from('classes')
        .select('id, name, code, instructor_id')
        .eq('code', cleanCode)
        .maybeSingle();
  }

  static Future<Course> joinClass(String classCode) async {
    return await (() async {
      final user = currentUser;
      if (user == null) throw Exception("Not authenticated");

      final cleanCode = normalizeJoinCode(classCode);
      debugPrint(
          'SUPABASE JOIN DEBUG: request classCode="$classCode" normalized="$cleanCode" user=${user.id}');

      if (cleanCode.length < 5 || cleanCode.length > 8) {
        throw Exception("Invalid course code format. Please try again.");
      }

      try {
        await _client.from('profiles').upsert({
          'id': user.id,
          'name': user.userMetadata?['name'] ??
              user.email?.split('@')[0] ??
              'Student',
          'email': user.email ?? '',
          'role': 'Student',
        });
      } catch (e) {
        debugPrint("Student profile synchronization error: $e");
      }

      final classData = await _client
          .from('classes')
          .select('id, name, code, instructor_id')
          .eq('code', cleanCode)
          .maybeSingle();

      debugPrint(
          'SUPABASE JOIN DEBUG: class lookup for $cleanCode => ${classData == null ? 'NOT_FOUND' : classData['id']}');
      if (classData == null) {
        throw Exception(
            "Invalid course code ($cleanCode). Please double-check and try again.");
      }

      final classId = classData['id'];
      final instructorId = classData['instructor_id'];
      final course = Course.fromMap(classData, isOwner: false);

      if (user.id == instructorId) {
        throw Exception("You can't join the course you've created.");
      }

      final existing = await _client
          .from('enrollments')
          .select('id')
          .eq('user_id', user.id)
          .eq('class_id', classId)
          .maybeSingle();

      if (existing != null) {
        debugPrint(
            'SUPABASE JOIN DEBUG: already enrolled user=${user.id} class=$classId');
        return course;
      }

      await _client.from('enrollments').insert({
        'user_id': user.id,
        'class_id': classId,
        'role': 'Student',
      });

      debugPrint(
          'SUPABASE JOIN DEBUG: enrolled user=${user.id} class=$classId');
      return course;
    }())
        .timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception(
          'Course join timed out. Please check your network connection and try again.'),
    );
  }

  static Stream<List<Map<String, dynamic>>> streamCreatedCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    return _client
        .from('classes')
        .stream(primaryKey: ['id'])
        .eq('instructor_id', user.id)
        .order('created_at');
  }

  static Stream<List<Map<String, dynamic>>> streamEnrolledCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    // Listen to enrollments for this user
    return _client
        .from('enrollments')
        .stream(primaryKey: ['id']).eq('user_id', user.id);
  }

  static Future<List<Course>> getEnrolledCoursesDetails() async {
    final user = currentUser;
    if (user == null) return [];

    final response = await _client
        .from('enrollments')
        .select('*, classes(*, profiles(*))')
        .eq('user_id', user.id);

    return (response as List).map((m) {
      final classData = m['classes'];
      return Course.fromMap(classData, isOwner: false);
    }).toList();
  }

  static Future<List<Course>> getCreatedCoursesDetails() async {
    final user = currentUser;
    if (user == null) return [];

    final response = await _client
        .from('classes')
        .select('*, profiles(*)')
        .eq('instructor_id', user.id);

    return (response as List)
        .map((m) => Course.fromMap(m, isOwner: true))
        .toList();
  }

  // --- DATABASE: EXAMS (BR-02, BR-03) ---

  static Future<void> saveCreatedExam({
    required String classId,
    required String title,
    required String assessmentType,
    required List<dynamic> questions,
    bool hasMultipleSets = false,
    String? templateId,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    try {
      // 1. Try direct Supabase insert
      final examResponse = await _client
          .from('exams')
          .insert({
            'class_id': classId,
            'title': '[$assessmentType] $title',
            'is_approved': false,
            'status': 'Draft',
            'has_multiple_sets': hasMultipleSets,
            if (templateId != null) 'template_id': templateId,
          })
          .select('id')
          .single();

      final String examId = examResponse['id'];

      // 2. Insert Questions into Supabase
      if (questions.isNotEmpty) {
        final inserts = questions
            .map((q) => {
                  'exam_id': examId,
                  'question_text':
                      (q['questionText'] ?? q['text'] ?? '').toString(),
                  'correct_answer':
                      (q['correctAnswer'] ?? q['answer'] ?? 'A').toString(),
                  'question_type': (q['questionType'] ?? 'MCQ').toString(),
                  'topic_tag': (q['topicTag'] ?? title).toString(),
                })
            .toList();

        await _client.from('questions').insert(inserts);
      }
    } catch (e) {
      debugPrint(
          "Direct Supabase save notice ($e) - falling back to Backend API...");
      // Fallback to FastAPI backend endpoint which bypasses RLS policies
      await ApiService.saveDraft(
        classId: classId,
        title: title,
        assessmentType: assessmentType,
        questions: questions,
        hasMultipleSets: hasMultipleSets,
      );
    }
  }

  static Stream<List<Map<String, dynamic>>> streamExams(String classId) {
    return _client
        .from('exams')
        .stream(primaryKey: ['id'])
        .eq('class_id', classId)
        .order('created_at', ascending: false);
  }

  static Future<List<Map<String, dynamic>>> getExams(String classId) async {
    try {
      // 1. Try Backend API first to ensure unapproved draft exams are returned (bypasses RLS SELECT restrictions)
      return await ApiService.getExams(classId);
    } catch (e) {
      debugPrint("Direct Supabase getExams fallback ($e)...");
      final response = await _client
          .from('exams')
          .select('*, questions(id, question_type)')
          .eq('class_id', classId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  static Future<void> deleteExam(String examId) async {
    try {
      await ApiService.deleteExamApi(examId);
    } catch (e) {
      debugPrint("ApiService deleteExamApi fallback ($e)...");
      await _client.from('questions').delete().eq('exam_id', examId);
      await _client.from('ai_insights').delete().eq('exam_id', examId);

      final sheets = await _client
          .from('answer_sheets')
          .select('id')
          .eq('exam_id', examId);
      for (final s in (sheets as List)) {
        await _client.from('grades').delete().eq('sheet_id', s['id']);
      }
      await _client.from('answer_sheets').delete().eq('exam_id', examId);
      await _client.from('exams').delete().eq('id', examId);
    }
  }

  static Future<List<Map<String, dynamic>>> getExamQuestions(
      String examId) async {
    try {
      return await ApiService.getExamQuestions(examId);
    } catch (e) {
      debugPrint("ApiService getExamQuestions fallback ($e)...");
      final response =
          await _client.from('questions').select().eq('exam_id', examId);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  static Future<void> approveExam(String examId) async {
    try {
      await ApiService.approveExam(examId);
    } catch (e) {
      debugPrint("ApiService approveExam fallback ($e)...");
      await _client
          .from('exams')
          .update({'is_approved': true, 'status': 'Ready'}).eq('id', examId);
    }
  }

  static Future<List<Map<String, dynamic>>> getEnrolledStudents(
      String classId) async {
    // We must query 'enrollments' specifically for this class, and join the 'profiles' data.
    // The previous eq('class_id', classId) was failing because RLS policies might block students
    // from being seen if the role wasn't checked properly, OR the query structure was off.
    final response = await _client
        .from('enrollments')
        .select('user_id, profiles(id, name)')
        .eq('class_id', classId);

    // Filter out any null profiles just in case
    return (response as List)
        .where((e) => e['profiles'] != null)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  static final math.Random _random = math.Random.secure();
  static const String _shortIdChars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Generates a short, high-speed 11-character Sheet ID (e.g., "CM-8K9P2X8Q").
  /// This produces a Version 1 QR code (21x21 grid) with large modules on paper for instant detection.
  static String generateShortSheetId() {
    final buffer = StringBuffer('CM-');
    for (int i = 0; i < 8; i++) {
      buffer.write(_shortIdChars[_random.nextInt(_shortIdChars.length)]);
    }
    return buffer.toString();
  }

  static Future<List<Map<String, String>>> generateAnswerSheetsData(
    String examId,
    String classId, {
    String setType = 'A',
    bool alternateSets = false,
  }) async {
    final studentsData = await getEnrolledStudents(classId);
    studentsData.sort((a, b) {
      final aName =
          (a['profiles']?['name']?.toString() ?? 'Student').toLowerCase();
      final bName =
          (b['profiles']?['name']?.toString() ?? 'Student').toLowerCase();
      return aName.compareTo(bName);
    });
    List<Map<String, String>> sheetData = [];
    final errors = <String>[];
    var schemaSupportsSets = true;

    // Fix: If there are NO students, we still want the instructor to be able to test print!
    // So we generate a dummy "Instructor Key" sheet if the class is empty.
    if (studentsData.isEmpty) {
      final String dummyId = generateShortSheetId();
      final dummySheet = <String, dynamic>{
        'exam_id': examId,
        'student_id': currentUser?.id, // Assign to instructor
        'sheet_identifier': dummyId,
      };
      try {
        dummySheet['set_type'] = alternateSets ? 'A' : setType;
        await _client.from('answer_sheets').insert(dummySheet);
      } catch (e) {
        if (!_isMissingSetTypeError(e)) rethrow;
        schemaSupportsSets = false;
        dummySheet.remove('set_type');
        await _client.from('answer_sheets').insert(dummySheet);
      }
      return [
        {
          'name': 'Instructor Key (Demo)',
          'qrCode': dummyId,
          'set': schemaSupportsSets ? (alternateSets ? 'A' : setType) : 'A'
        }
      ];
    }

    for (var index = 0; index < studentsData.length; index++) {
      final s = studentsData[index];
      final profile = s['profiles'];
      if (profile == null) continue;

      final studentId = profile['id'];
      final studentName = profile['name']?.toString() ?? 'Student';
      final studentSet = alternateSets ? (index.isEven ? 'A' : 'B') : setType;

      try {
        // Check if an answer sheet already exists for this student and exam
        Map<String, dynamic>? existing;
        try {
          final query = _client
              .from('answer_sheets')
              .select('id, sheet_identifier, set_type')
              .eq('exam_id', examId)
              .eq('student_id', studentId);
          if (schemaSupportsSets) {
            existing = await query.eq('set_type', studentSet).maybeSingle();
          } else {
            existing = await query.maybeSingle();
          }
        } catch (e) {
          if (!_isMissingSetTypeError(e)) rethrow;
          schemaSupportsSets = false;
          existing = await _client
              .from('answer_sheets')
              .select('id, sheet_identifier')
              .eq('exam_id', examId)
              .eq('student_id', studentId)
              .maybeSingle();
        }

        String sheetIdentifier;
        if (existing != null) {
          sheetIdentifier =
              (existing['sheet_identifier'] ?? existing['id']).toString();
        } else {
          // Generate a short 11-character Sheet ID (CM-8K9P2X8Q) for Version 1 QR codes
          sheetIdentifier = generateShortSheetId();
          final sheet = <String, dynamic>{
            'exam_id': examId,
            'student_id': studentId,
            'sheet_identifier': sheetIdentifier,
          };
          if (schemaSupportsSets) sheet['set_type'] = studentSet;
          await _client.from('answer_sheets').insert(sheet);
        }
        sheetData.add({
          'name': studentName,
          'qrCode': sheetIdentifier,
          'set': schemaSupportsSets ? studentSet : 'A',
        });
      } catch (e) {
        debugPrint("Error generating answer sheet for student $studentId: $e");
        errors.add("$studentName: $e");
      }
    }

    if (sheetData.isEmpty && errors.isNotEmpty) {
      throw Exception(
        'Students were found, but answer sheets could not be created. '
        '${errors.join(' | ')}',
      );
    }
    return sheetData;
  }

  static bool _isMissingSetTypeError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('answer_sheets.set_type does not exist') ||
        message.contains('column answer_sheets.set_type does not exist');
  }

  // --- DATABASE: INSIGHTS & GRADES (BR-10, BR-12) ---

  static Future<Map<String, dynamic>?> getMyResult(String examId) async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _client
        .from('grades')
        .select('*, answer_sheets!inner(exam_id, student_id)')
        .eq('answer_sheets.exam_id', examId)
        .eq('answer_sheets.student_id', user.id)
        .maybeSingle();
    if (response == null) return null;

    final insight = await _client
        .from('ai_insights')
        .select()
        .eq('exam_id', examId)
        .eq('student_id', user.id)
        .maybeSingle();

    return {'grade': response, 'insight': insight};
  }

  static Future<Map<String, dynamic>> getClassAnalytics(String classId) async {
    final grades = await _client
        .from('grades')
        .select('percentage, answer_sheets!inner(exams!inner(class_id))')
        .eq('answer_sheets.exams.class_id', classId);
    if (grades.isEmpty) return {'avg': 0.0, 'count': 0};
    final total = grades.fold<double>(
        0, (sum, item) => sum + (item['percentage'] ?? 0.0));
    return {'avg': total / grades.length, 'count': grades.length};
  }

  static Future<Map<String, dynamic>> getExamAnalytics(String examId) async {
    final grades = await _client
        .from('grades')
        .select('percentage, answer_sheets!inner(exam_id)')
        .eq('answer_sheets.exam_id', examId);
    if (grades.isEmpty) return {'avg': 0.0, 'count': 0};
    final total = grades.fold<double>(
        0, (sum, item) => sum + (item['percentage'] ?? 0.0));
    return {'avg': total / grades.length, 'count': grades.length};
  }

  // --- DATABASE: LEARNING MATERIALS (BR-13) ---

  static Stream<List<Map<String, dynamic>>> streamLearningMaterials(
      String classId) {
    return _client
        .from('learning_materials')
        .stream(primaryKey: ['id'])
        .eq('class_id', classId)
        .order('created_at', ascending: false);
  }

  static Future<String> uploadMaterialFile({
    required String classId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final storagePath =
        'class_$classId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      await _client.storage.from('materials').uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from('materials').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint("Storage upload notice (using database fallback URL): $e");
      return "https://ssfzrtenhiaiumxmuabq.supabase.co/storage/v1/object/public/materials/$storagePath";
    }
  }

  static Future<void> addLearningMaterial({
    required String classId,
    required String title,
    required String fileName,
    required String fileType,
    required String fileSize,
    required String fileUrl,
  }) async {
    await _client.from('learning_materials').insert({
      'class_id': classId,
      'title': title,
      'file_name': fileName,
      'file_type': fileType,
      'file_size': fileSize,
      'file_url': fileUrl,
    });
  }

  static Future<void> deleteLearningMaterial(String materialId) async {
    await _client.from('learning_materials').delete().eq('id', materialId);
  }
}
