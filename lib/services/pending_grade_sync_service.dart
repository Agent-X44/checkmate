import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';

/// Keeps only evaluated JSON on this device until each sheet is saved.
/// A queue entry is independent of capture order, assessment, and printed set.
class PendingGradeSyncService {
  static Future<int>? _drain;
  static String get _key {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in before saving grades.');
    return 'pending_grade_sync_v1_$userId';
  }

  static Future<List<Map<String, dynamic>>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((item) => Map<String, dynamic>.from(item)),
    );
  }

  // Serializes every read-modify-write of the queue, so an enqueue and a
  // finished upload never overwrite each other's change.
  static Future<void> _writes = Future.value();
  static Future<T> _locked<T>(Future<T> Function() action) {
    final run = _writes.then((_) => action());
    _writes = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<void> enqueue({
    required String examId,
    required Map<String, dynamic> result,
  }) async {
    final sheetId = result['sheet_id']?.toString();
    if (examId.isEmpty || sheetId == null || sheetId.isEmpty) {
      throw ArgumentError('A resolved assessment and sheet ID are required.');
    }
    // Does not wait for uploads in flight: confirming a sheet stays instant.
    await _locked(() async {
      final entries = await pending();
      entries.removeWhere((entry) => entry['result']?['sheet_id'] == sheetId);
      entries.add({'exam_id': examId, 'result': result});
      await _save(entries);
    });
  }

  static Future<int> syncPending() =>
      _drain ??= _syncPending().whenComplete(() {
        _drain = null;
      });

  static Future<int> _syncPending() async {
    final attempted = <String>{};
    var saved = 0;
    // Re-read each round so sheets queued during this drain are sent too.
    while (true) {
      final next = (await pending())
          .map(jsonEncode)
          .where((encoded) => !attempted.contains(encoded))
          .firstOrNull;
      if (next == null) return saved;
      attempted.add(next);
      final entry = jsonDecode(next) as Map<String, dynamic>;
      try {
        await ApiService.batchSyncResults(
          examId: entry['exam_id'] as String,
          results: [Map<String, dynamic>.from(entry['result'])],
        );
      } catch (_) {
        // Leave this exact local evaluation queued for an explicit retry.
        continue;
      }
      // Remove only the sent version; a rescan queued meanwhile stays.
      await _locked(() async {
        final entries = await pending();
        entries.removeWhere((e) => jsonEncode(e) == next);
        await _save(entries);
      });
      saved++;
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = await prefs.setString(_key, jsonEncode(entries));
    if (!persisted) {
      throw StateError('Could not keep the grade pending on this device.');
    }
  }
}
