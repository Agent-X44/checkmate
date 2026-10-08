import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_build.dart';
import '../models/omr/template_calibration.dart';

class DeveloperTemplateStore {
  static const _key = 'checkmate_developer_templates_v1';
  static Future<List<TemplateCalibration>> load() async {
    if (!AppBuild.developerTools) return [];
    final prefs = await SharedPreferences.getInstance();
    try {
      final values = jsonDecode(prefs.getString(_key) ?? '[]') as List;
      return values
          .map((v) => TemplateCalibration.fromMap(Map<String, dynamic>.from(v)))
          .toList();
    } catch (_) {
      // A damaged local preset must not stop the offline workspace opening.
      return [];
    }
  }

  static Future<TemplateCalibration?> active(String baseTemplateId) async {
    final rows = await load();
    final matching =
        rows.where((r) => r.baseTemplateId == baseTemplateId).toList();
    return matching.isEmpty ? null : matching.last;
  }

  static Future<void> save(TemplateCalibration config) async {
    if (!AppBuild.developerTools) {
      throw StateError('Developer edition required');
    }
    // Validate before writing. Update a named profile without duplicating it.
    final validated = TemplateCalibration.fromMap(config.toMap());
    final rows = await load();
    rows.removeWhere((r) =>
        r.name == validated.name &&
        r.baseTemplateId == validated.baseTemplateId);
    rows.add(validated);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key, jsonEncode(rows.map((r) => r.toMap()).toList()))) {
      throw StateError('Could not save template on this device');
    }
  }
}
