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

  static Future<void> enqueue({
    required String examId,
    required Map<String, dynamic> result,
  }) async {
    if (_drain != null) await _drain;
    final sheetId = result['sheet_id']?.toString();
    if (examId.isEmpty || sheetId == null || sheetId.isEmpty) {
      throw ArgumentError('A resolved assessment and sheet ID are required.');
    }
    final entries = await pending();
    entries.removeWhere((entry) => entry['result']?['sheet_id'] == sheetId);
    entries.add({'exam_id': examId, 'result': result});
    await _save(entries);
  }

  static Future<int> syncPending() =>
      _drain ??= _syncPending().whenComplete(() {
        _drain = null;
      });

  static Future<int> _syncPending() async {
    final entries = await pending();
    var saved = 0;
    for (final entry in List<Map<String, dynamic>>.from(entries)) {
      try {
        await ApiService.batchSyncResults(
          examId: entry['exam_id'] as String,
          results: [Map<String, dynamic>.from(entry['result'])],
        );
        entries.remove(entry);
        await _save(entries);
        saved++;
      } catch (_) {
        // Leave this exact local evaluation queued for an explicit retry.
      }
    }
    return saved;
  }

  static Future<void> _save(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = await prefs.setString(_key, jsonEncode(entries));
    if (!persisted) {
      throw StateError('Could not keep the grade pending on this device.');
    }
  }
}
