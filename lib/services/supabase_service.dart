import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/course.dart';

/// Service responsible for Supabase Authentication and Database interactions.
/// 
/// Enforces:
/// - BR-01: Course/Class Management (Create/Join)
/// - BR-12: Security & Row Level Security (Privacy)
class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

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
      const webClientId = '521288904900-cjt4oidq41d7er31gev8tddsfsc30s5q.apps.googleusercontent.com';

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
        debugPrint("GOOGLE_AUTH: ERROR - idToken is null. Check Web Client ID configuration.");
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

  // --- DATABASE: COURSES (BR-01) ---

  static Future<void> createClass({
    required String name,
    required String code,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    // Self-healing: Ensure profile exists before creating class (BR-01)
    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'name': user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? 'User',
        'email': user.email ?? '',
        'role': 'Instructor',
      });
    } catch (e) {
      debugPrint("Profile synchronization error: $e");
    }

    await _client.from('classes').insert({
      'name': name,
      'code': code,
      'instructor_id': user.id,
    });
  }

  static Future<void> joinClass(String classCode) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    final classData = await _client
        .from('classes')
        .select('id, instructor_id')
        .eq('code', classCode)
        .single();
    
    final classId = classData['id'];
    final instructorId = classData['instructor_id'];

    if (user.id == instructorId) {
      throw Exception("You are the instructor of this course and cannot join as a student.");
    }

    await _client.from('enrollments').insert({
      'user_id': user.id,
      'class_id': classId,
      'role': 'Student',
    });
  }

  static Stream<List<Map<String, dynamic>>> streamCreatedCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    return _client.from('classes').stream(primaryKey: ['id']).eq('instructor_id', user.id).order('created_at');
  }

  static Stream<List<Map<String, dynamic>>> streamEnrolledCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    // Listen to enrollments for this user
    return _client.from('enrollments').stream(primaryKey: ['id']).eq('user_id', user.id);
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
    
    return (response as List).map((m) => Course.fromMap(m, isOwner: true)).toList();
  }

  // --- DATABASE: EXAMS (BR-02, BR-03) ---

  static Stream<List<Map<String, dynamic>>> streamExams(String classId) {
    return _client.from('exams').stream(primaryKey: ['id']).eq('class_id', classId).order('created_at', ascending: false);
  }

  static Future<void> approveExam(String examId) async {
    await _client.from('exams').update({'is_approved': true, 'status': 'Ready'}).eq('id', examId);
  }

  static Future<List<Map<String, dynamic>>> getEnrolledStudents(String classId) async {
    final response = await _client.from('enrollments').select('profiles(id, name)').eq('class_id', classId);
    return List<Map<String, dynamic>>.from(response);
  }

  // --- DATABASE: INSIGHTS & GRADES (BR-10, BR-12) ---

  static Future<Map<String, dynamic>?> getMyResult(String examId) async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _client.from('grades').select('*, answer_sheets!inner(exam_id, student_id)').eq('answer_sheets.exam_id', examId).eq('answer_sheets.student_id', user.id).maybeSingle();
    if (response == null) return null;

    final insight = await _client.from('ai_insights').select().eq('exam_id', examId).eq('student_id', user.id).maybeSingle();

    return {'grade': response, 'insight': insight};
  }

  static Future<Map<String, dynamic>> getClassAnalytics(String classId) async {
    final grades = await _client.from('grades').select('percentage, answer_sheets!inner(exam_id)').eq('answer_sheets.exam_id', classId);
    if (grades.isEmpty) return {'avg': 0.0, 'count': 0};
    final total = grades.fold<double>(0, (sum, item) => sum + (item['percentage'] ?? 0.0));
    return {'avg': total / grades.length, 'count': grades.length};
  }
}
