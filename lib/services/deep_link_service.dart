import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:checkmate/models/course.dart';
import 'supabase_service.dart';
import '../utils/ui_utils.dart';

/// Global Key for Navigator to allow deep-link driven UI navigation & prompts
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Deep Link Service: Handles Google Classroom style invitation links
/// Enforces:
/// - BR-01: Direct Course Invitation & Automatic Join Workflow via Deep/App Links
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingJoinCode;
  bool _processingPendingJoin = false;
  static final StreamController<Course> _joinedCourses =
      StreamController<Course>.broadcast();

  String? get pendingJoinCode => _pendingJoinCode;
  static Stream<Course> get joinedCourses => _joinedCourses.stream;
  static const String inviteHost = 'noelpi-checkmate-backend.hf.space';

  /// Opens the app when installed, otherwise the web landing offers the APK.
  static String buildInviteLink(String joinCode) {
    return Uri.https(inviteHost, '/join', {
      'code': _normalizeCode(joinCode),
    }).toString();
  }

  /// Builds custom scheme deep link for direct app launch
  static String buildCustomSchemeLink(String joinCode) {
    return Uri(
      scheme: 'checkmate',
      host: 'join',
      queryParameters: {'code': _normalizeCode(joinCode)},
    ).toString();
  }

  static String _normalizeCode(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  static String? extractJoinCode(Uri uri) {
    var code = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
    if ((code == null || code.isEmpty) && uri.pathSegments.isNotEmpty) {
      final segments = uri.pathSegments;
      if (segments.first.toLowerCase() == 'join' && segments.length > 1) {
        code = segments[1];
      } else if (segments.length == 1 &&
          segments.first.toLowerCase() != 'join') {
        code = segments.first;
      }
    }
    if (code == null) return null;
    final normalized = _normalizeCode(code);
    return RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(normalized) ? normalized : null;
  }

  static void notifyCourseJoined(Course course) {
    _joinedCourses.add(course);
  }

  /// Initialize App Links listener
  void initialize() {
    _linkSubscription?.cancel();

    // 1. Listen to incoming deep links while app is open
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleUri(uri);
      },
      onError: (err) {
        debugPrint('DeepLink error stream: $err');
      },
    );

    // 2. Handle initial link when app was opened from cold start
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    }).catchError((err) {
      debugPrint('DeepLink initial link error: $err');
    });
  }

  /// Parse URI and extract course join code
  String? _extractCodeFromUri(Uri uri) {
    return extractJoinCode(uri);
  }

  /// Handle incoming Uri
  Future<void> _handleUri(Uri uri) async {
    final code = _extractCodeFromUri(uri);
    if (code == null) return;

    debugPrint('DEEP_LINK: Extracted join code -> $code');

    final user = SupabaseService.currentUser;
    if (user != null) {
      // User is logged in -> Execute direct course join workflow
      await processJoinCode(code);
    } else {
      // User is not logged in -> Store pending join code for post-login auto-join
      _pendingJoinCode = code;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_join_code', code);
      } catch (e) {
        debugPrint('Failed to persist pending join code: $e');
      }

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        CheckMateUi.showTopPrompt(
          context,
          'Invitation received for course $code! Please log in to join.',
          isError: false,
        );
      }
    }
  }

  /// Process joining a course using join code
  Future<void> processJoinCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    final context = navigatorKey.currentContext;

    debugPrint(
        'DEEP LINK JOIN DEBUG: start joinCode=$normalizedCode user=${SupabaseService.currentUser?.id ?? 'null'}');

    try {
      if (context != null && context.mounted) {
        CheckMateUi.showTopPrompt(
            context, 'Joining course ($normalizedCode)...',
            isError: false);
      }

      final course = await SupabaseService.joinClass(normalizedCode).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception(
            'Course join timed out. Please check your network and try again.'),
      );

      debugPrint(
          'DEEP LINK JOIN DEBUG: success for $normalizedCode -> ${course.name}');
      notifyCourseJoined(course);
      _pendingJoinCode = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_join_code');
      } catch (error) {
        debugPrint('Could not clear the saved invitation code: $error');
      }

      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        CheckMateUi.showTopPrompt(
          currentCtx,
          'Successfully joined course: ${course.name}!',
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('DEEP LINK JOIN DEBUG: failed for $normalizedCode :: $e');
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        final isAlreadyEnrolled = errorMsg.contains('already enrolled');
        CheckMateUi.showTopPrompt(
          currentCtx,
          errorMsg,
          isError: !isAlreadyEnrolled,
        );
      }
    }
  }

  /// Check & process any stored pending join code after login
  Future<void> checkPendingJoinOnLogin() async {
    if (_processingPendingJoin || SupabaseService.currentUser == null) return;
    String? code = _pendingJoinCode;

    if (code == null || code.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        code = prefs.getString('pending_join_code');
      } catch (_) {}
    }

    if (code != null && code.isNotEmpty) {
      debugPrint('DEEP_LINK: Processing pending join code after auth -> $code');
      _processingPendingJoin = true;
      try {
        await processJoinCode(code);
      } finally {
        _processingPendingJoin = false;
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
