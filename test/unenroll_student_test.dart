import 'dart:convert';
import 'dart:io';

import 'package:checkmate/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Future<void> Function(HttpRequest) respond;

  Future<void> reply(HttpRequest request, Object data) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request));
    await Supabase.initialize(
      url: 'http://127.0.0.1:${server.port}',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {
        'id': 'teacher-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'teacher@example.test',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-09-28T00:00:00Z',
      },
    }));
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
  });

  test('course owner deletes only the selected student enrollment', () async {
    var deleteCount = 0;
    respond = (request) async {
      if (request.uri.path == '/rest/v1/classes') {
        expect(request.uri.queryParameters['id'], 'eq.class-1');
        expect(request.uri.queryParameters['instructor_id'], 'eq.teacher-1');
        await reply(request, [
          {'id': 'class-1'}
        ]);
      } else if (request.uri.path == '/rest/v1/enrollments') {
        expect(request.method, 'DELETE');
        expect(request.uri.queryParameters['class_id'], 'eq.class-1');
        expect(request.uri.queryParameters['user_id'], 'eq.student-1');
        expect(request.uri.queryParameters['role'], 'eq.Student');
        deleteCount++;
        await reply(request, [
          {'id': 'enrollment-1'}
        ]);
      } else {
        fail('Unexpected request: ${request.uri}');
      }
    };

    await SupabaseService.unenrollStudent('class-1', 'student-1');
    expect(deleteCount, 1);
  });

  test('a non-owner cannot delete another student enrollment', () async {
    var deleteCount = 0;
    respond = (request) async {
      if (request.uri.path == '/rest/v1/classes') {
        await reply(request, []);
      } else {
        deleteCount++;
        fail('Non-owner attempted an enrollment delete.');
      }
    };

    await expectLater(
      SupabaseService.unenrollStudent('class-1', 'student-1'),
      throwsStateError,
    );
    expect(deleteCount, 0);
  });
}
