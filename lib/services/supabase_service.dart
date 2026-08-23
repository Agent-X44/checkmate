import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  // --- AUTHENTICATION ---

  /// Sign up with email and password (BR-01)
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    return response;
  }

  /// Sign in with email and password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Google Sign-In Implementation
  static Future<AuthResponse?> signInWithGoogle() async {
    // Web Client ID is required for the backend 'handshake'
    const webClientId = '521288904900-cjt4oidq41d7er31gev8tddsfsc30s5q.apps.googleusercontent.com';

    final GoogleSignIn googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
    );
    
    final googleUser = await googleSignIn.signIn();
    final googleAuth = await googleUser?.authentication;
    final idToken = googleAuth?.idToken;
    final accessToken = googleAuth?.accessToken;

    if (idToken == null || accessToken == null) {
      return null;
    }

    return await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  /// Sign out
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // --- USER DATA ---

  static User? get currentUser => _client.auth.currentUser;

  static Session? get currentSession => _client.auth.currentSession;

  // --- DATABASE: COURSES (BR-01) ---

  /// Create a new class as an instructor
  static Future<void> createClass({
    required String name,
    required String code,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.from('classes').insert({
      'name': name,
      'code': code,
      'instructor_id': user.id,
    });
  }

  /// Join an existing class as a student
  static Future<void> joinClass(String classCode) async {
    final user = currentUser;
    if (user == null) throw Exception("Not authenticated");

    // 1. Find the class by code
    final classData = await _client
        .from('classes')
        .select('id')
        .eq('code', classCode)
        .single();

    final classId = classData['id'];

    // 2. Create enrollment
    await _client.from('enrollments').insert({
      'user_id': user.id,
      'class_id': classId,
      'role': 'Student',
    });
  }

  /// Stream of courses where the user is an instructor
  static Stream<List<Map<String, dynamic>>> streamCreatedCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    
    return _client
        .from('classes')
        .stream(primaryKey: ['id'])
        .eq('instructor_id', user.id)
        .order('created_at');
  }

  /// Stream of courses where the user is enrolled as a student
  static Stream<List<Map<String, dynamic>>> streamEnrolledCourses() {
    final user = currentUser;
    if (user == null) return Stream.value([]);

    // This requires a join or a complex stream. 
    // For the demo, we can fetch once or use a simpler approach if RLS is set.
    return _client
        .from('enrollments')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at');
  }

  // --- DATABASE: EXAMS (BR-02, BR-03) ---

  /// Stream of exams for a specific class
  static Stream<List<Map<String, dynamic>>> streamExams(String classId) {
    return _client
        .from('exams')
        .stream(primaryKey: ['id'])
        .eq('class_id', classId)
        .order('created_at', ascending: false);
  }

  /// Stream of enrolled students for a class
  static Stream<List<Map<String, dynamic>>> streamClassStudents(String classId) {
    // In production, we'd use a view or a complex query. 
    // For the demo stream, we'll fetch once or use a simpler approach.
    return _client
        .from('enrollments')
        .stream(primaryKey: ['id'])
        .eq('class_id', classId);
  }

  /// Approve an exam to unlock sheet generation (BR-03)
  static Future<void> approveExam(String examId) async {
    await _client
        .from('exams')
        .update({'is_approved': true, 'status': 'Ready'})
        .eq('id', examId);
  }

  /// Fetch enrolled students for an exam's class (BR-04)
  static Future<List<Map<String, dynamic>>> getEnrolledStudents(String classId) async {
    final response = await _client
        .from('enrollments')
        .select('profiles(id, name)')
        .eq('class_id', classId);
    
    return List<Map<String, dynamic>>.from(response);
  }

  // --- DATABASE: INSIGHTS & GRADES (BR-10, BR-12) ---

  /// Fetch my grade and AI insight for a specific exam
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

    // Fetch AI Insight if available
    final insight = await _client
        .from('ai_insights')
        .select()
        .eq('exam_id', examId)
        .eq('student_id', user.id)
        .maybeSingle();

    return {
      'grade': response,
      'insight': insight,
    };
  }

  /// Fetch aggregated analytics for a class
  static Future<Map<String, dynamic>> getClassAnalytics(String classId) async {
    final grades = await _client
        .from('grades')
        .select('percentage, answer_sheets!inner(exam_id)')
        .eq('answer_sheets.exam_id', classId); // Simplified for demo
    
    if (grades.isEmpty) return {'avg': 0.0, 'count': 0};

    final total = grades.fold<double>(0, (sum, item) => sum + (item['percentage'] ?? 0.0));
    return {
      'avg': total / grades.length,
      'count': grades.length,
    };
  }
}
