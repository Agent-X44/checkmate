import 'dart:io';

import 'package:checkmate/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late void Function(HttpRequest) respond;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request));
    await Supabase.initialize(
      url: 'http://127.0.0.1:${server.port}',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
  });

  test('fetches only graded sheets for the requested exam', () async {
    respond = (request) {
      expect(request.uri.path, '/rest/v1/answer_sheets');
      expect(request.uri.queryParameters['exam_id'], 'eq.exam-1');
      expect(request.uri.queryParameters['select'], contains('grades!inner('));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
          '[{"id":"sheet-1","grades":[{"score":8,"percentage":80}],'
          '"profiles":{"name":"Student"}}]');
      request.response.close();
    };
    final results = await ApiService.getExamResults('exam-1');
    expect(results.single['grades'][0]['score'], 8);
    expect(results.single['profiles']['name'], 'Student');
  });

  test('empty exam does not fall back to other exams', () async {
    var requests = 0;
    respond = (request) {
      requests++;
      expect(request.uri.queryParameters['exam_id'], 'eq.empty-exam');
      request.response.headers.contentType = ContentType.json;
      request.response.write('[]');
      request.response.close();
    };
    expect(await ApiService.getExamResults('empty-exam'), isEmpty);
    expect(requests, 1);
  });

  test('database failures propagate instead of returning empty results', () async {
    respond = (request) {
      request.response.statusCode = 403;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
          '{"code":"42501","message":"permission denied"}');
      request.response.close();
    };
    await expectLater(ApiService.getExamResults('exam-1'),
        throwsA(isA<PostgrestException>()));
  });
}
