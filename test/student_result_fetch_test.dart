import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checkmate/models/omr/processed_sheet.dart';
import 'package:checkmate/models/omr/qr_data.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/cv/bubble_detection_service.dart';
import 'package:checkmate/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Future<void> Function(HttpRequest) respond;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request));
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

  Future<void> jsonResponse(HttpRequest request, dynamic data,
      {int status = 200}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  test('instructor detail filters the selected student and exact sheet',
      () async {
    var requests = 0;
    respond = (request) async {
      requests++;
      expect(request.uri.path, '/rest/v1/grades');
      expect(request.uri.queryParameters['answer_sheets.exam_id'], 'eq.exam-1');
      expect(request.uri.queryParameters['answer_sheets.student_id'],
          'eq.student-1');
      expect(request.uri.queryParameters['sheet_id'], 'eq.sheet-1');
      expect(request.uri.queryParameters['limit'], '1');
      await jsonResponse(request, {
        'sheet_id': 'sheet-1',
        'score': 1,
        'answers': [
          {'answer': 'B', 'isCorrect': false}
        ],
        'student_insight': {
          'source': 'ai',
          'insight': {'performanceSummary': 'Saved feedback'}
        },
      });
    };
    final result = await SupabaseService.getStudentResult('exam-1',
        studentId: 'student-1', sheetId: 'sheet-1');
    expect(result!['grade']['sheet_id'], 'sheet-1');
    expect(result['grade']['answers'][0]['answer'], 'B');
    expect(
        result['insight']['insight']['performanceSummary'], 'Saved feedback');
    expect(requests, 1);
  });

  test('student result uses authenticated released-result endpoint', () async {
    respond = (request) async {
      expect(request.uri.path, '/my-exam-result/exam-1');
      expect(request.headers.value('Authorization'), 'Bearer test-access-token');
      await jsonResponse(request, {
        'grade': {
          'sheet_id': 'sheet-1',
          'answers': [
            {'answer': 'B', 'correct_answer': 'C', 'isCorrect': false}
          ]
        },
        'insight': null,
      });
    };
    final result = await SupabaseService.getMyResult('exam-1');
    expect(result!['grade']['answers'][0]['answer'], 'B');
    expect(result['grade']['answers'][0]['correct_answer'], 'C');
  });

  test('unreleased result is unavailable, but server errors propagate', () async {
    respond = (request) => jsonResponse(
        request, {'detail': 'Released result not found'}, status: 404);
    expect(await SupabaseService.getMyResult('exam-1'), isNull);
    respond = (request) => jsonResponse(
        request, {'detail': 'Database error'}, status: 500);
    await expectLater(SupabaseService.getMyResult('exam-1'), throwsException);
  });

  test('a result query error is not treated as a missing grade', () async {
    respond = (request) => jsonResponse(
        request, {'message': 'permission denied', 'code': '42501'},
        status: 403);
    await expectLater(
        SupabaseService.getStudentResult('exam-1',
            studentId: 'student-1', sheetId: 'sheet-1'),
        throwsA(isA<PostgrestException>()));
  });

  test('finish session sends one authenticated batch with no images', () async {
    var requests = 0;
    respond = (request) async {
      requests++;
      expect(request.uri.path, '/batch-save-grades');
      expect(
          request.headers.value('Authorization'), 'Bearer test-access-token');
      final data = jsonDecode(await utf8.decoder.bind(request).join());
      expect(data['results'], hasLength(2));
      expect(data['results'][0]['answers'][0]['isCorrect'], true);
      await jsonResponse(request, {'status': 'success', 'saved_count': 2});
    };
    await ApiService.batchSyncResults(examId: 'exam-1', results: [
      {
        'sheet_id': 'sheet-1',
        'score': 1,
        'total': 1,
        'answers': [
          {'isCorrect': true}
        ]
      },
      {
        'sheet_id': 'sheet-2',
        'score': 0,
        'total': 1,
        'answers': [
          {'isCorrect': false}
        ]
      },
    ]);
    expect(requests, 1);
  });

  test('partial or failed saves propagate and cannot unlock analysis',
      () async {
    respond = (request) =>
        jsonResponse(request, {'status': 'success', 'saved_count': 0});
    await expectLater(
        ApiService.batchSyncResults(examId: 'exam-1', results: [
          {'sheet_id': 'sheet-1', 'score': 1, 'total': 1},
        ]),
        throwsStateError);
    respond = (request) =>
        jsonResponse(request, {'detail': 'Save failed'}, status: 500);
    await expectLater(
        ApiService.batchSyncResults(examId: 'exam-1', results: [
          {'sheet_id': 'sheet-1', 'score': 1, 'total': 1},
        ]),
        throwsException);
  });

  test(
      'personal AI requests identify the saved sheet, not the signed-in teacher score',
      () async {
    respond = (request) async {
      expect(request.uri.path, '/student-insight');
      expect(
          request.headers.value('Authorization'), 'Bearer test-access-token');
      final data = jsonDecode(await utf8.decoder.bind(request).join());
      expect(data,
          {'exam_id': 'exam-1', 'sheet_id': 'sheet-1', 'regenerate': false});
      await jsonResponse(request, {
        'source': 'ai',
        'insight': {'performanceSummary': 'Feedback'}
      });
    };
    final response = await ApiService.getStudentInsight(
        examId: 'exam-1', sheetId: 'sheet-1');
    expect(response['source'], 'ai');
  });

  test(
      'sync snapshot preserves printed order, local grading and excludes all image buffers',
      () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sheet = ProcessedSheet(
      warpedImage: bytes,
      thresholdImage: bytes,
      answerRegion: bytes,
      questionImages: [bytes],
      templateName: 'Test',
      detectedSet: 'B',
      qrData: QrData(
          studentName: 'Student',
          examCode: 'exam-1',
          course: 'Course',
          examTitle: 'Test',
          sheetIdentifier: 'CM-ABC123'),
      results: [
        BubbleResult(answer: 'B', confidence: 1, isCorrect: true),
        BubbleResult(answer: null, confidence: 0, isCorrect: false),
      ],
      questionDetails: const [
        {
          'id': 'q-2',
          'question_text': 'Second printed first',
          'correct_answer': 'B',
          'topic_tag': 'Maps'
        },
        {
          'id': 'q-1',
          'question_text': 'First printed second',
          'correct_answer': 'A',
          'question_type': 'TF'
        },
      ],
    );
    final data = sheet.copyWith().toSyncResult();
    expect(data.keys.toSet(), {'sheet_id', 'score', 'total', 'answers'});
    expect(data['score'], 1);
    expect(data['answers'][0]['question_id'], 'q-2');
    expect(data['answers'][0]['correct_answer'], 'B');
    expect(data['answers'][1]['question_number'], 2);
    expect(data['answers'][1]['answer'], isNull);
    expect(jsonEncode(data), isNot(contains('Image')));
  });
}
