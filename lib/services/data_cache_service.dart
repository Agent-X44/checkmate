import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheChange {
  final String userId;
  final String kind;
  final String id;
  final dynamic value;
  final Map<String, dynamic>? changedRow;
  const CacheChange(this.userId, this.kind, this.id, this.value,
      [this.changedRow]);
}

/// Account-scoped snapshots. Successful writes notify every visible screen
/// before disk persistence; old network requests cannot overwrite mutations.
class DataCacheService {
  static String? Function() userIdProvider = () => null;
  static final _changes = StreamController<CacheChange>.broadcast(sync: true);
  static Stream<CacheChange> get changes => _changes.stream;
  static final Map<String, dynamic> _memory = {};
  static final Map<String, int> _revisions = {};
  static final Map<String, Future<void>> _writes = {};
  static String? _key(String kind, String id) {
    final user = userIdProvider();
    return user == null ? null : 'checkmate_cache_v2_${user}_${kind}_$id';
  }

  static dynamic _copy(dynamic value) => jsonDecode(jsonEncode(value));
  static int revision(String kind, String id) =>
      _revisions[_key(kind, id)] ?? 0;

  static Future<dynamic> _read(String kind, String id) async {
    final key = _key(kind, id);
    if (key == null) return null;
    if (_memory.containsKey(key)) return _copy(_memory[key]);
    try {
      final prefs = await SharedPreferences.getInstance();
      // A mutation can arrive while preferences are loading.
      if (_memory.containsKey(key)) return _copy(_memory[key]);
      final raw = prefs.getString(key);
      if (raw != null && _key(kind, id) == key) {
        final value = jsonDecode(raw);
        _memory[key] = value;
        return _copy(value);
      }
    } catch (error) {
      debugPrint('Cache read failed: $error');
    }
    return null;
  }

  static Future<void> _save(String kind, String id, dynamic value,
      {int? expectedRevision,
      bool mutation = false,
      Map<String, dynamic>? changedRow}) async {
    final key = _key(kind, id);
    final user = userIdProvider();
    if (key == null || user == null) {
      return;
    }
    if (expectedRevision != null && revision(kind, id) != expectedRevision) {
      return;
    }
    final snapshot = _copy(value);
    if (mutation) _revisions[key] = (_revisions[key] ?? 0) + 1;
    _memory[key] = snapshot;
    _changes.add(CacheChange(
        user,
        kind,
        id,
        _copy(snapshot),
        changedRow == null
            ? null
            : Map<String, dynamic>.from(_copy(changedRow))));
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, jsonEncode(snapshot));
      } catch (error) {
        debugPrint('Cache persistence failed: $error');
      }
    });
    _writes[key] = next;
    await next;
    if (identical(_writes[key], next)) _writes.remove(key);
  }

  static Future<List<Map<String, dynamic>>> _list(
      String kind, String id) async {
    final value = await _read(kind, id);
    return value is List ? List<Map<String, dynamic>>.from(value) : [];
  }

  static Future<void> upsert(
      String kind, String id, Map<String, dynamic> row) async {
    final user = userIdProvider();
    var rows = await _list(kind, id);
    final key = _key(kind, id);
    if (key != null && _memory[key] is List) {
      rows = List<Map<String, dynamic>>.from(_copy(_memory[key]));
    }
    if (user != userIdProvider()) {
      return;
    }
    final index = rows.indexWhere((item) => item['id'] == row['id']);
    if (index < 0) {
      rows.insert(0, row);
    } else {
      rows[index] = {...rows[index], ...row};
    }
    await _save(kind, id, rows, mutation: true, changedRow: row);
  }

  static Future<void> removeRows(
      String kind, String id, Iterable<String> ids) async {
    final user = userIdProvider();
    var rows = await _list(kind, id);
    final key = _key(kind, id);
    if (key != null && _memory[key] is List) {
      rows = List<Map<String, dynamic>>.from(_copy(_memory[key]));
    }
    if (user != userIdProvider()) {
      return;
    }
    rows.removeWhere((row) => ids.contains(row['id']));
    await _save(kind, id, rows, mutation: true);
  }

  static Future<void> saveCourses(List<Map<String, dynamic>> rows,
          {int? expectedRevision}) =>
      _save('courses', 'mine', rows, expectedRevision: expectedRevision);
  static Future<List<Map<String, dynamic>>> getCourses() =>
      _list('courses', 'mine');
  static Future<void> saveClassAnalytics(
          String id, Map<String, dynamic> data) =>
      _save('analytics', id, data);
  static Future<Map<String, dynamic>?> getClassAnalytics(String id) async {
    final value = await _read('analytics', id);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static Future<void> saveLearningMaterials(
          String id, List<Map<String, dynamic>> rows,
          {int? expectedRevision}) =>
      _save('materials', id, rows, expectedRevision: expectedRevision);
  static Future<List<Map<String, dynamic>>> getLearningMaterials(String id) =>
      _list('materials', id);
  static Future<void> saveExams(String id, List<Map<String, dynamic>> rows,
          {int? expectedRevision}) =>
      _save('exams', id, rows, expectedRevision: expectedRevision);
  static Future<List<Map<String, dynamic>>> getExams(String id) =>
      _list('exams', id);
  static Future<void> saveEnrolledStudents(
          String id, List<Map<String, dynamic>> rows) =>
      _save('students', id, rows);
  static Future<List<Map<String, dynamic>>> getEnrolledStudents(String id) =>
      _list('students', id);
  static void clearMemoryCache() {
    _memory.clear();
  }
}
