import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_build.dart';
import '../models/omr/template_calibration.dart';

/// Named local grading templates for the developer edition.
///
/// Each layout uses its built-in template unless a saved one has been
/// explicitly selected for it. Saving selects the saved template; choosing
/// "built-in" clears the selection without deleting anything. Installs from
/// before selections existed therefore start on the built-in template.
class DeveloperTemplateStore {
  static const _key = 'checkmate_developer_templates_v1';
  static const _activeKey = 'checkmate_developer_active_templates_v1';

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

  /// Selected template name per base layout ID.
  static Future<Map<String, String>> _selection() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return Map<String, String>.from(
          jsonDecode(prefs.getString(_activeKey) ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// The saved template selected for [baseTemplateId], or null when the
  /// layout uses its built-in template.
  static Future<TemplateCalibration?> active(String baseTemplateId) async {
    if (!AppBuild.developerTools) return null;
    final name = (await _selection())[baseTemplateId];
    if (name == null) return null;
    for (final row in await load()) {
      if (row.baseTemplateId == baseTemplateId && row.name == name) return row;
    }
    return null;
  }

  /// Only the selected templates, one per layout, for the OMR reader.
  static Future<List<TemplateCalibration>> activeProfiles() async {
    if (!AppBuild.developerTools) return [];
    final selection = await _selection();
    return [
      for (final row in await load())
        if (selection[row.baseTemplateId] == row.name) row
    ];
  }

  /// Selects a saved template by [name], or the built-in one when null.
  static Future<void> setActive(String baseTemplateId, String? name) async {
    if (!AppBuild.developerTools) {
      throw StateError('Developer edition required');
    }
    final selection = await _selection();
    if (name == null) {
      selection.remove(baseTemplateId);
    } else {
      selection[baseTemplateId] = name;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_activeKey, jsonEncode(selection))) {
      throw StateError('Could not save the template choice on this device');
    }
  }

  static Future<void> save(TemplateCalibration config,
      {bool activate = true}) async {
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
    await _write(rows);
    if (activate) await setActive(validated.baseTemplateId, validated.name);
  }

  static Future<void> delete(String baseTemplateId, String name) async {
    if (!AppBuild.developerTools) {
      throw StateError('Developer edition required');
    }
    final rows = await load();
    rows.removeWhere(
        (r) => r.baseTemplateId == baseTemplateId && r.name == name);
    await _write(rows);
    if ((await _selection())[baseTemplateId] == name) {
      await setActive(baseTemplateId, null);
    }
  }

  static Future<void> _write(List<TemplateCalibration> rows) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key, jsonEncode(rows.map((r) => r.toMap()).toList()))) {
      throw StateError('Could not save template on this device');
    }
  }
}
