import 'dart:convert';
import 'dart:io';

import 'package:checkmate/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
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

  test('a new student joining does not give others a second sheet', () async {
    final inserted = <Map>[];
    respond = (request) async {
      final query = request.uri.queryParameters;
      switch ((request.method, request.uri.path)) {
        case ('GET', '/rest/v1/exams'):
          await reply(request, {'class_id': 'class-1', 'is_approved': true});
        case ('GET', '/rest/v1/enrollments'):
          await reply(request, [
            {
              'user_id': 'bea',
              'profiles': {'id': 'bea', 'name': 'Bea'}
            },
            {
              'user_id': 'aaron',
              'profiles': {'id': 'aaron', 'name': 'Aaron'}
            },
          ]);
        case ('GET', '/rest/v1/answer_sheets'):
          // Bea was printed Set A before Aaron joined and sorted ahead of her.
          expect(query.containsKey('set_type'), isFalse);
          await reply(
              request,
              query['student_id'] == 'eq.bea'
                  ? [
                      {
                        'id': 'sheet-bea',
                        'sheet_identifier': 'CM-BEA23456',
                        'set_type': 'A'
                      }
                    ]
                  : []);
        case ('POST', '/rest/v1/answer_sheets'):
          inserted.add(jsonDecode(await utf8.decodeStream(request)) as Map);
          await reply(request, []);
        default:
          fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    final sheets = await SupabaseService.generateAnswerSheetsData(
        'exam-1', 'class-1',
        alternateSets: true);

    expect(sheets.map((s) => (s['name'], s['set'])),
        [('Aaron', 'A'), ('Bea', 'A')]);
    expect(sheets[1]['qrCode'], 'CM-BEA23456');
    expect(inserted.map((s) => s['student_id']), ['aaron']);
  });
}
