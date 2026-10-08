import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'deep_link_service.dart';

class AppNotification {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? classId;
  final String? examId;
  final String? studentId;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.classId,
    required this.examId,
    required this.studentId,
    required this.createdAt,
    required this.readAt,
  });

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> row) => AppNotification(
        id: row['id'].toString(),
        kind: row['kind'].toString(),
        title: row['title']?.toString() ?? '',
        body: row['body']?.toString() ?? '',
        classId: row['class_id']?.toString(),
        examId: row['exam_id']?.toString(),
        studentId: row['related_student_id']?.toString(),
        createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
        readAt: row['read_at'] == null
            ? null
            : DateTime.parse(row['read_at'].toString()).toLocal(),
      );
}

class NotificationService {
  static const _channelId = 'checkmate_updates';
  static const _channelName = 'CheckMate updates';
  static const _supportedKinds = {
    'announcement',
    'message',
    'module_upload',
    'result',
  };
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localInitialized = false;
  static bool _localAvailable = false;
  static String? _activeUserId;
  static String? _registeredToken;
  static String? _pendingTapId;
  static bool _notificationBaselineLoaded = false;
  static final Set<String> _knownNotificationIds = {};
  static StreamSubscription<List<AppNotification>>? _persistedNotifications;
  static StreamSubscription<RemoteMessage>? _foregroundMessages;
  static StreamSubscription<RemoteMessage>? _openedMessages;
  static StreamSubscription<String>? _tokenRefresh;

  static SupabaseClient get _db => Supabase.instance.client;

  static Stream<List<AppNotification>> streamMine() {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);
    return _db
        .from('user_notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .map((rows) => rows.map(AppNotification.fromMap).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  static int notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> initialize() async {
    if (_localInitialized || !_isAndroid) return;
    try {
      final initialized = await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          _openNotificationFromPayload(response.payload);
        },
      );
      _localAvailable = initialized == true;
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description:
                'Messages, announcements, course materials and results',
            importance: Importance.high,
          ));
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _openNotificationFromPayload(
            launchDetails?.notificationResponse?.payload);
      }
      _localInitialized = _localAvailable;
    } catch (error, stackTrace) {
      _localAvailable = false;
      debugPrint(
          'Android local notifications could not initialize: $error\n$stackTrace');
    }
  }

  static Future<void> startForCurrentUser() async {
    await initialize();
    final userId = _db.auth.currentUser?.id;
    if (userId == null || !_isAndroid) {
      _flushPendingTap();
      return;
    }
    if (_activeUserId == userId) {
      _listenToPersistedNotifications(userId);
      try {
        if (Firebase.apps.isEmpty) await Firebase.initializeApp();
        final messaging = FirebaseMessaging.instance;
        _listenToFirebaseMessages(userId);
        await _requestLocalNotificationPermission();
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final authorized =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        if (authorized && _registeredToken == null) {
          final token = await messaging.getToken();
          if (token != null) await _registerToken(token, userId);
        }
      } on FirebaseException catch (error) {
        debugPrint(
            'Could not retry notification token registration: ${error.message}');
      } catch (error) {
        debugPrint('Could not retry notification setup: $error');
      }
      _flushPendingTap();
      return;
    }
    if (_activeUserId != null) await stopForCurrentUser();
    _activeUserId = userId;
    _listenToPersistedNotifications(userId);
    await _requestLocalNotificationPermission();

    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      _listenToFirebaseMessages(userId);
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('Android notification permission was not granted.');
        _flushPendingTap();
        return;
      }

      final token = await messaging.getToken();
      if (token != null) await _registerToken(token, userId);
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) _openRemoteMessage(initialMessage);
      _flushPendingTap();
    } on FirebaseException catch (error, stackTrace) {
      await _cancelFirebaseSubscriptions();
      debugPrint(
          'Firebase notifications are unavailable: ${error.message}\n$stackTrace');
      _flushPendingTap();
    } catch (error, stackTrace) {
      await _cancelFirebaseSubscriptions();
      debugPrint('Could not start Android notifications: $error\n$stackTrace');
      _flushPendingTap();
    }
  }

  static Future<void> _requestLocalNotificationPermission() async {
    if (!_localAvailable) return;
    try {
      final granted = await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (granted == false) {
        debugPrint('Android local notification permission was not granted.');
      }
    } catch (error) {
      debugPrint('Could not request Android notification permission: $error');
    }
  }

  static void _listenToPersistedNotifications(String userId) {
    if (_persistedNotifications != null) return;
    _notificationBaselineLoaded = false;
    _knownNotificationIds.clear();
    _persistedNotifications = streamMine().listen(
      (notifications) {
        if (_activeUserId != userId) return;
        if (!_notificationBaselineLoaded) {
          _knownNotificationIds
              .addAll(notifications.map((notice) => notice.id));
          _notificationBaselineLoaded = true;
          return;
        }
        for (final notice in notifications) {
          if (_knownNotificationIds.add(notice.id)) {
            unawaited(_showPersistedNotification(notice));
          }
        }
      },
      onError: (Object error) {
        debugPrint('Notification updates could not be received: $error');
        final subscription = _persistedNotifications;
        _persistedNotifications = null;
        _notificationBaselineLoaded = false;
        unawaited(subscription?.cancel());
      },
      onDone: () {
        _persistedNotifications = null;
        _notificationBaselineLoaded = false;
      },
    );
  }

  static void _listenToFirebaseMessages(String userId) {
    _foregroundMessages ??= FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_showForegroundMessage(message)),
      onError: (Object error) =>
          debugPrint('Foreground notification stream failed: $error'),
    );
    _openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _openRemoteMessage,
      onError: (Object error) =>
          debugPrint('Notification tap stream failed: $error'),
    );
    _tokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token, userId)),
      onError: (Object error) =>
          debugPrint('Notification token refresh failed: $error'),
    );
  }

  static Future<void> _registerToken(String token, String userId) async {
    if (_activeUserId != userId || _db.auth.currentUser?.id != userId) return;
    try {
      final oldToken = _registeredToken;
      if (oldToken != null && oldToken != token) {
        try {
          await _db
              .from('user_notification_tokens')
              .delete()
              .eq('user_id', userId)
              .eq('token', oldToken);
        } catch (error) {
          debugPrint(
              'Could not remove the previous notification token: $error');
        }
      }
      await _db.from('user_notification_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      _registeredToken = token;
    } catch (error) {
      debugPrint('Could not register notification device token: $error');
    }
  }

  static Future<void> stopForCurrentUser() async {
    final userId = _activeUserId;
    final token = _registeredToken;
    _activeUserId = null;
    _registeredToken = null;
    _pendingTapId = null;
    await _persistedNotifications?.cancel();
    _persistedNotifications = null;
    _notificationBaselineLoaded = false;
    _knownNotificationIds.clear();
    await _cancelFirebaseSubscriptions();
    if (userId == null || token == null || _db.auth.currentUser?.id != userId) {
      return;
    }
    try {
      await _db
          .from('user_notification_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);
    } catch (error) {
      debugPrint('Could not unregister notification device token: $error');
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } on FirebaseException catch (error) {
      debugPrint(
          'Could not invalidate notification device token: ${error.message}');
    } catch (error) {
      debugPrint('Could not invalidate notification device token: $error');
    }
  }

  static Future<void> _cancelFirebaseSubscriptions() async {
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
    await _tokenRefresh?.cancel();
    _foregroundMessages = null;
    _openedMessages = null;
    _tokenRefresh = null;
  }

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    if (!_localAvailable) return;
    final data = message.data;
    final kind = data['kind'];
    final id = data['id'];
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (id == null ||
        !_supportedKinds.contains(kind) ||
        title == null ||
        body == null) {
      debugPrint('Ignoring incomplete or unsupported push notification.');
      return;
    }
    if (!_knownNotificationIds.add(id)) return;
    await _showLocalNotification(
      id: id,
      kind: kind!,
      title: title,
      body: body,
      data: data,
    );
  }

  static Future<void> _showPersistedNotification(
      AppNotification notification) async {
    await _showLocalNotification(
      id: notification.id,
      kind: notification.kind,
      title: notification.title,
      body: notification.body,
      data: {
        'id': notification.id,
        'kind': notification.kind,
        if (notification.classId != null) 'class_id': notification.classId!,
        if (notification.examId != null) 'exam_id': notification.examId!,
        if (notification.studentId != null)
          'related_student_id': notification.studentId!,
      },
    );
  }

  static Future<void> _showLocalNotification({
    required String id,
    required String kind,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    if (!_localAvailable || !_supportedKinds.contains(kind)) return;
    try {
      await _localNotifications.show(
        id: notificationId(id),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Messages, announcements, course materials and results',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(data),
      );
    } catch (error) {
      debugPrint('Could not display foreground notification: $error');
    }
  }

  static void _openRemoteMessage(RemoteMessage message) {
    _openNotificationId(message.data['id']?.toString());
  }

  static void _openNotificationFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) {
        _openNotificationId(data['id']?.toString());
      }
    } on FormatException catch (error) {
      debugPrint('Ignoring malformed notification tap payload: $error');
    }
  }

  static void _openNotificationId(String? id) {
    if (id == null || id.isEmpty) return;
    if (_db.auth.currentUser == null) {
      _pendingTapId = id;
      return;
    }
    _pendingTapId = id;
    _flushPendingTap();
  }

  static void _flushPendingTap() {
    final id = _pendingTapId;
    final navigator = navigatorKey.currentState;
    if (id == null || navigator == null || _db.auth.currentUser == null) return;
    _pendingTapId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pushNotificationRoute(navigator, id));
    });
  }

  static Future<void> _pushNotificationRoute(
    NavigatorState navigator,
    String id,
  ) async {
    try {
      await navigator.pushNamed<void>('/notifications', arguments: id);
    } catch (error) {
      debugPrint('Could not open tapped notification: $error');
    }
  }

  static Future<void> markRead(String id) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    await _db
        .from('user_notifications')
        .update({
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('recipient_id', userId);
  }

  static Future<void> markAllRead(
      Iterable<AppNotification> notifications) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    final ids = notifications
        .where((notice) => notice.isUnread)
        .map((notice) => notice.id)
        .toList();
    if (ids.isEmpty) return;
    await _db
        .from('user_notifications')
        .update({
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('recipient_id', userId)
        .inFilter('id', ids);
  }
}
