import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:checkmate/services/data_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? user;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DataCacheService.clearMemoryCache();
    user = 'teacher';
    DataCacheService.userIdProvider = () => user;
  });

  test('snapshots persist and stay separated by account', () async {
    await DataCacheService.saveExams('course', [{'id': 'exam', 'is_approved': true}]);
    DataCacheService.clearMemoryCache();
    expect((await DataCacheService.getExams('course')).single['id'], 'exam');
    user = 'student';
    expect(await DataCacheService.getExams('course'), isEmpty);
    user = null;
    expect(await DataCacheService.getExams('course'), isEmpty);
    user = 'teacher';
    expect((await DataCacheService.getExams('course')).single['id'], 'exam');
  });

  test('old shared-account keys are never reused', () async {
    SharedPreferences.setMockInitialValues({'checkmate_cache_exams_course': '[{"id":"private"}]'});
    expect(await DataCacheService.getExams('course'), isEmpty);
  });

  test('late network responses cannot erase a newly created draft', () async {
    final revision = DataCacheService.revision('exams', 'course');
    await DataCacheService.upsert('exams', 'course', {'id': 'new', 'status': 'Draft'});
    await DataCacheService.saveExams('course', [], expectedRevision: revision);
    DataCacheService.clearMemoryCache();
    expect((await DataCacheService.getExams('course')).single['id'], 'new');
  });

  test('status changes merge metadata and notify listeners immediately', () async {
    await DataCacheService.saveExams('course', [{'id': 'exam', 'questions': [{'id': 'q'}], 'is_approved': false}]);
    CacheChange? event;
    final subscription = DataCacheService.changes.listen((change) => event = change);
    await DataCacheService.upsert('exams', 'course', {'id': 'exam', 'is_approved': true, 'status': 'Ready'});
    expect(event!.userId, 'teacher');
    expect(event!.changedRow!['status'], 'Ready');
    expect((event!.value as List).single['questions'], [{'id': 'q'}]);
    await subscription.cancel();
  });

  test('concurrent create and join mutations keep both courses', () async {
    await Future.wait([
      DataCacheService.upsert('courses', 'mine', {'id': 'created', '_is_owner': true}),
      DataCacheService.upsert('courses', 'mine', {'id': 'joined', '_is_owner': false}),
    ]);
    final rows = await DataCacheService.getCourses();
    expect(rows.map((row) => row['id']).toSet(), {'created', 'joined'});
    DataCacheService.clearMemoryCache();
    expect((await DataCacheService.getCourses()).length, 2);
  });

  test('deletion cannot be undone by an older refresh', () async {
    await DataCacheService.saveExams('course', [{'id': 'removed'}]);
    final revision = DataCacheService.revision('exams', 'course');
    await DataCacheService.removeRows('exams', 'course', ['removed']);
    await DataCacheService.saveExams('course', [{'id': 'removed'}], expectedRevision: revision);
    expect(await DataCacheService.getExams('course'), isEmpty);
  });

  test('returned nested values cannot modify cached data', () async {
    await DataCacheService.saveExams('course', [{'id': 'exam', 'questions': [{'id': 'original'}]}]);
    final rows = await DataCacheService.getExams('course');
    rows.single['questions'][0]['id'] = 'changed';
    expect((await DataCacheService.getExams('course')).single['questions'][0]['id'], 'original');
  });

  test('an account switch during a mutation cannot write to the next account', () async {
    final write = DataCacheService.upsert('exams', 'course', {'id': 'private'});
    user = 'student';
    await write;
    expect(await DataCacheService.getExams('course'), isEmpty);
  });

  test('a confirmed upload is cached before a later network refresh', () async {
    final revision = DataCacheService.revision('materials', 'course');
    await DataCacheService.upsert('materials', 'course', {'id': 'file', 'file_url': 'https://example.test/file'});
    await DataCacheService.saveLearningMaterials('course', [], expectedRevision: revision);
    DataCacheService.clearMemoryCache();
    expect((await DataCacheService.getLearningMaterials('course')).single['id'], 'file');
  });
}
