import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';
import 'package:checkmate/models/course.dart';
import 'supabase_service.dart';
import '../utils/ui_utils.dart';

/// Global Key for Navigator to allow deep-link driven UI navigation & prompts
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Deep Link Service: Handles Google Classroom style invitation links
/// Enforces:
/// - BR-01: Course invitations require student confirmation before enrollment
class DeepLinkService {
  static const _pendingJoinPreference = 'pending_invite_token';
  static const _handledJoinPreference = 'handled_invite_token';
  static const _handledJoinCooldown = Duration(minutes: 5);

  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingJoinCode;
  bool _processingPendingJoin = false;
  String? _lastReceivedJoinCode;
  DateTime? _lastReceivedJoinAt;
  String? _activeJoinCode;
  static final StreamController<Course> _joinedCourses =
      StreamController<Course>.broadcast();

  String? get pendingJoinCode => _pendingJoinCode;
  static Stream<Course> get joinedCourses => _joinedCourses.stream;
  static const String inviteHost = 'noelpi-checkmate-backend.hf.space';

  /// Opens the app when installed, otherwise the web landing offers the APK.
  static String buildInviteLink(String inviteToken) {
    return Uri.https(inviteHost, '/join', {
      'inviteToken': _normalizeInviteToken(inviteToken),
    }).toString();
  }

  /// Builds a private custom-scheme link for direct app launch.
  static String buildCustomSchemeLink(String inviteToken) {
    return Uri(
      scheme: 'checkmate',
      host: 'join',
      queryParameters: {'inviteToken': _normalizeInviteToken(inviteToken)},
    ).toString();
  }

  static String _normalizeInviteToken(String value) {
    final token = value.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid course invitation link.');
    }
    return token;
  }

  static bool isInviteToken(String value) =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value.trim());

  static String? extractInviteToken(Uri uri) {
    final token = uri.queryParameters['inviteToken'];
    return token != null && isInviteToken(token) ? token.toLowerCase() : null;
  }

  static String _normalizeCode(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  static String? extractJoinCode(Uri uri) {
    var code = uri.queryParameters['joinCode'] ?? uri.queryParameters['code'];
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

  /// Handle incoming private invitation links. Legacy course-code links are ignored.
  Future<void> _handleUri(Uri uri) async {
    final token = extractInviteToken(uri);
    if (token == null) return;

    if (await _wasRecentlyHandled(token)) {
      await _clearPendingJoinCode();
      debugPrint('DEEP_LINK: Ignoring recently handled invitation');
      return;
    }

    final now = DateTime.now();
    if (_lastReceivedJoinCode == token &&
        _lastReceivedJoinAt != null &&
        now.difference(_lastReceivedJoinAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastReceivedJoinCode = token;
    _lastReceivedJoinAt = now;

    debugPrint('DEEP_LINK: Received private course invitation');

    final user = SupabaseService.currentUser;
    if (user != null) {
      _pendingJoinCode = token;
      await _savePendingJoinCode(token);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(checkPendingJoinOnLogin());
      });
    } else {
      _pendingJoinCode = token;
      await _savePendingJoinCode(token);

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        CheckMateUi.showTopPrompt(
          context,
          'Course invitation received. Please log in to join.',
          isError: false,
          fallbackOverlay: navigatorKey.currentState?.overlay,
        );
      }
    }
  }

  /// Process joining a course using a private invitation token.
  Future<void> processJoinCode(String token) async {
    final inviteToken = _normalizeInviteToken(token);
    final context = navigatorKey.currentContext;

    if (_activeJoinCode == inviteToken) return;
    _activeJoinCode = inviteToken;

    if (context == null || !context.mounted) {
      await _savePendingJoinCode(inviteToken);
      _activeJoinCode = null;
      return;
    }

    var progressDialogShown = false;
    try {
      final shouldJoin = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Join course?'),
          content: const Text('Would you like to join this course?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('JOIN COURSE'),
            ),
          ],
        ),
      );

      if (shouldJoin != true) {
        await _markJoinHandled(inviteToken);
        await _clearPendingJoinCode();
        return;
      }

      // Consume the link before the request so a failure cannot prompt again on next login.
      await _markJoinHandled(inviteToken);
      await _clearPendingJoinCode();
      showDialog<void>(
        context: navigatorKey.currentContext ?? context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Joining course...')),
            ],
          ),
        ),
      );
      progressDialogShown = true;

      final course =
          await SupabaseService.joinCourseWithInvitation(inviteToken).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception(
            'Course join timed out. Please check your network and try again.'),
      );

      debugPrint('DEEP LINK JOIN DEBUG: joined course ${course.name}');
      final navigator = navigatorKey.currentState;
      if (progressDialogShown && navigator != null && navigator.canPop()) {
        navigator.pop();
        progressDialogShown = false;
      }
      notifyCourseJoined(course);

      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        try {
          CheckMateUi.showTopPrompt(
            currentCtx,
            'Successfully joined course: ${course.name}!',
            isError: false,
            fallbackOverlay: navigatorKey.currentState?.overlay,
          );
        } catch (e) {
          debugPrint('Error showing success prompt: $e');
        }
      }
    } catch (e, stackTrace) {
      final navigator = navigatorKey.currentState;
      if (progressDialogShown && navigator != null && navigator.canPop()) {
        navigator.pop();
        progressDialogShown = false;
      }
      debugPrint('DEEP LINK JOIN DEBUG: invitation join failed :: $e');
      debugPrintStack(
          stackTrace: stackTrace, label: 'Deep link course join failure');
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      final currentCtx = navigatorKey.currentContext;
      if (currentCtx != null && currentCtx.mounted) {
        try {
          await showDialog<void>(
            context: currentCtx,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Could not join course'),
              content: Text(errorMsg),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } catch (e) {
          debugPrint('Error showing error dialog: $e');
        }
      }
    } finally {
      _activeJoinCode = null;
    }
  }

  /// Check & process any stored pending join code after login
  Future<void> checkPendingJoinOnLogin() async {
    if (_processingPendingJoin || SupabaseService.currentUser == null) return;
    String? code = _pendingJoinCode;

    if (code == null || code.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        code = prefs.getString(_pendingJoinPreference);
      } catch (_) {}
    }

    if (code != null && code.isNotEmpty) {
      if (await _wasRecentlyHandled(code)) {
        await _clearPendingJoinCode();
        return;
      }
      if (!isInviteToken(code)) {
        await _clearPendingJoinCode();
        return;
      }
      debugPrint('DEEP_LINK: Processing pending private invitation after auth');
      _processingPendingJoin = true;
      try {
        await processJoinCode(code);
      } finally {
        _processingPendingJoin = false;
      }
    }
  }

  Future<void> _savePendingJoinCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingJoinPreference, code);
    } catch (error) {
      debugPrint('Failed to persist pending join code: $error');
    }
  }

  Future<void> _clearPendingJoinCode() async {
    _pendingJoinCode = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingJoinPreference);
    } catch (error) {
      debugPrint('Could not clear the saved invitation code: $error');
    }
  }

  Future<void> _markJoinHandled(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _handledJoinPreference,
        '$code:${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (error) {
      debugPrint('Could not save handled invitation state: $error');
    }
  }

  Future<bool> _wasRecentlyHandled(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_handledJoinPreference);
      if (value == null) return false;

      final separator = value.lastIndexOf(':');
      if (separator < 0 || value.substring(0, separator) != code) return false;
      final timestamp = int.tryParse(value.substring(separator + 1));
      if (timestamp == null) return false;

      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      if (age >= Duration.zero && age < _handledJoinCooldown) return true;
      await prefs.remove(_handledJoinPreference);
    } catch (error) {
      debugPrint('Could not read handled invitation state: $error');
    }
    return false;
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
