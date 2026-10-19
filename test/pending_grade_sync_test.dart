import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/pending_grade_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  final uploads = <String>[];
  final firstUploadArrived = Completer<void>();
  final releaseFirstUpload = Completer<void>();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      final sheetId = (body['results'] as List).single['sheet_id'] as String;
      uploads.add(sheetId);
      if (sheetId == 'CM-AAAAAAAA') {
        firstUploadArrived.complete();
        await releaseFirstUpload.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'status': 'success', 'saved_count': 1}));
      await request.response.close();
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:${server.port}',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    ApiService.setBaseUrl('http://127.0.0.1:${server.port}');
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {
        'id': 'teacher',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'teacher@example.test',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-09-26T00:00:00Z',
      },
    }));
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
  });

  Map<String, dynamic> result(String sheetId) =>
      {'sheet_id': sheetId, 'score': 1, 'total': 1, 'answers': []};

  test('a sheet confirmed during an upload is queued at once and sent',
      () async {
    await PendingGradeSyncService.enqueue(
        examId: 'exam-1', result: result('CM-AAAAAAAA'));
    final drain = PendingGradeSyncService.syncPending();
    await firstUploadArrived.future;

    // The first upload is still waiting on the server.
    await PendingGradeSyncService.enqueue(
            examId: 'exam-2', result: result('CM-BBBBBBBB'))
        .timeout(const Duration(seconds: 2));
    expect((await PendingGradeSyncService.pending()).length, 2);

    releaseFirstUpload.complete();
    expect(await drain, 2);
    expect(uploads, ['CM-AAAAAAAA', 'CM-BBBBBBBB']);
    expect(await PendingGradeSyncService.pending(), isEmpty);
  });
}
