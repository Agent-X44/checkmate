import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  String? get pendingJoinCode => _pendingJoinCode;

  /// Builds standardized invitation link for a course (Web host coming soon)
  static String buildInviteLink(String joinCode) {
    // Commented out web domain link until website host is deployed
    // return 'https://checkmate.app/join?code=${joinCode.trim().toUpperCase()}';
    return 'checkmate://join?code=${joinCode.trim().toUpperCase()}';
  }

  /// Builds custom scheme deep link for direct app launch
  static String buildCustomSchemeLink(String joinCode) {
    return 'checkmate://join?code=${joinCode.trim().toUpperCase()}';
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
    // 1. Try query parameter ?code=... or ?joinCode=...
    String? code = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
    
    // 2. Try path segment: /join/CODE or /join?code=...
    if ((code == null || code.isEmpty) && uri.pathSegments.isNotEmpty) {
      if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'join') {
        code = uri.pathSegments[1];
      } else if (uri.pathSegments.length == 1 && uri.pathSegments.first != 'join') {
        code = uri.pathSegments.first;
      }
    }

    if (code != null && code.trim().isNotEmpty) {
      return code.trim().toUpperCase();
    }
    return null;
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
    final context = navigatorKey.currentContext;

    try {
      if (context != null && context.mounted) {
        CheckMateUi.showTopPrompt(context, 'Joining course ($code)...', isError: false);
      }

      final course = await SupabaseService.joinClass(code);

      _pendingJoinCode = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_join_code');
      } catch (_) {}

      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        CheckMateUi.showTopPrompt(
          currentCtx,
          'Successfully joined course: ${course.name}!',
          isError: false,
        );
      }
    } catch (e) {
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
    String? code = _pendingJoinCode;

    if (code == null || code.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        code = prefs.getString('pending_join_code');
      } catch (_) {}
    }

    if (code != null && code.isNotEmpty) {
      debugPrint('DEEP_LINK: Processing pending join code after auth -> $code');
      await processJoinCode(code);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
