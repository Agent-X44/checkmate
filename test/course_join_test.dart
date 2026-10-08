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

  Future<void> replyEmpty(HttpRequest request) async {
    request.response.statusCode = HttpStatus.noContent;
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
        'id': 'student-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'student@example.test',
        'app_metadata': {},
        'user_metadata': {'name': 'Student'},
        'created_at': '2026-09-28T00:00:00Z',
      },
    }));
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
  });

  test('joining uses validated course data and creates one enrollment',
      () async {
    var profileSynced = false;
    var enrollmentCreated = false;

    respond = (request) async {
      if (request.uri.path == '/rest/v1/profiles') {
        profileSynced = true;
        await replyEmpty(request);
      } else if (request.uri.path == '/rest/v1/rpc/join_course_with_code') {
        expect(
            jsonDecode(await utf8.decodeStream(request))['p_code'], 'JOIN42');
        enrollmentCreated = true;
        await reply(request, [
          {
            'id': 'class-1',
            'name': 'Physics',
            'instructor_id': 'teacher-1',
          }
        ]);
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    final course = await SupabaseService.joinClass(' join-42 ');

    expect(course.id, 'class-1');
    expect(course.name, 'Physics');
    expect(profileSynced, isTrue);
    expect(enrollmentCreated, isTrue);
  });

  test('rejects a course code rejected by the protected join RPC', () async {
    respond = (request) async {
      if (request.uri.path == '/rest/v1/profiles') {
        await replyEmpty(request);
      } else if (request.uri.path == '/rest/v1/rpc/join_course_with_code') {
        request.response.statusCode = HttpStatus.badRequest;
        await reply(request, {'message': 'Invalid course code'});
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    await expectLater(
      SupabaseService.joinClass('JOIN42'),
      throwsA(isA<Exception>()),
    );
  });

  test('joining with a private invitation uses the token redemption RPC',
      () async {
    final token = List.filled(64, 'a').join();
    respond = (request) async {
      if (request.uri.path == '/rest/v1/profiles') {
        await replyEmpty(request);
      } else if (request.uri.path ==
          '/rest/v1/rpc/join_course_with_invitation') {
        final payload = jsonDecode(await utf8.decodeStream(request));
        expect(payload['p_token'], token);
        await reply(request, [
          {
            'id': 'class-1',
            'name': 'Physics',
            'instructor_id': 'teacher-1',
          }
        ]);
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    final course = await SupabaseService.joinCourseWithInvitation(token);
    expect(course.id, 'class-1');
    expect(course.name, 'Physics');
  });

  test('rejects an expired invitation reported by the redemption RPC',
      () async {
    respond = (request) async {
      if (request.uri.path == '/rest/v1/profiles') {
        await replyEmpty(request);
      } else if (request.uri.path ==
          '/rest/v1/rpc/join_course_with_invitation') {
        request.response.statusCode = HttpStatus.badRequest;
        await reply(request, {'message': 'Invitation link expired'});
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    await expectLater(
      SupabaseService.joinCourseWithInvitation(List.filled(64, 'a').join()),
      throwsA(isA<Exception>()),
    );
  });

  test('already-enrolled students are not inserted again', () async {
    respond = (request) async {
      if (request.uri.path == '/rest/v1/profiles') {
        await replyEmpty(request);
      } else if (request.uri.path == '/rest/v1/rpc/join_course_with_code') {
        await reply(request, [
          {
            'id': 'class-1',
            'name': 'Physics',
            'instructor_id': 'teacher-1',
          }
        ]);
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    final course = await SupabaseService.joinClass('JOIN42');
    expect(course.id, 'class-1');
    expect(course.id, 'class-1');
  });

  test('course lists only request columns allowed by database permissions',
      () async {
    var loadedCreatedCourses = false;
    var loadedOwnedCode = false;
    var loadedEnrolledCourses = false;

    respond = (request) async {
      if (request.uri.path == '/rest/v1/classes') {
        expect(
          request.uri.queryParameters['select'],
          'id,name,instructor_id,created_at,profiles(name)',
        );
        loadedCreatedCourses = true;
        await reply(request, [
          {
            'id': 'class-1',
            'name': 'Physics',
            'instructor_id': 'student-1',
            'created_at': '2026-10-03T00:00:00Z',
            'profiles': {'name': 'Instructor'},
          }
        ]);
      } else if (request.uri.path == '/rest/v1/rpc/get_owned_course_code') {
        loadedOwnedCode = true;
        await reply(request, 'JOIN42');
      } else if (request.uri.path == '/rest/v1/enrollments') {
        expect(
          request.uri.queryParameters['select'],
          'id,user_id,class_id,role,classes(id,name,instructor_id,created_at,profiles(name))',
        );
        loadedEnrolledCourses = true;
        await reply(request, [
          {
            'id': 'enrollment-1',
            'user_id': 'student-1',
            'class_id': 'class-1',
            'role': 'Student',
            'classes': {
              'id': 'class-1',
              'name': 'Physics',
              'instructor_id': 'teacher-1',
              'created_at': '2026-10-03T00:00:00Z',
              'profiles': {'name': 'Teacher'},
            },
          }
        ]);
      } else {
        fail('Unexpected request: ${request.method} ${request.uri}');
      }
    };

    final created = await SupabaseService.getCreatedCoursesDetails();
    final enrolled = await SupabaseService.getEnrolledCoursesDetails();

    expect(loadedCreatedCourses, isTrue);
    expect(loadedOwnedCode, isTrue);
    expect(loadedEnrolledCourses, isTrue);
    expect(created.single.code, 'JOIN42');
    expect(enrolled.single.name, 'Physics');
  });
}
