import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_build.dart';
import '../models/omr/template_calibration.dart';

/// Developer-only `.json` files for grading templates: the same format as
/// the copy/paste dialogs, so files, clipboard text and the built-in
/// template export are interchangeable.
abstract final class TemplateFileService {
  static String encode(TemplateCalibration config) =>
      const JsonEncoder.withIndent('  ').convert(config.toMap());

  /// Parses and validates template JSON. Unknown keys are ignored.
  static TemplateCalibration decode(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      throw const FormatException('This file is not valid JSON.');
    }
    if (value is! Map) {
      throw const FormatException('Expected one template object.');
    }
    return TemplateCalibration.fromMap(Map<String, dynamic>.from(value));
  }

  static String fileName(TemplateCalibration config) {
    final slug = config.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '${slug.isEmpty ? 'template' : slug}.json';
  }

  /// Opens the system save dialog. Returns the chosen path, or null when
  /// cancelled.
  static Future<String?> save(TemplateCalibration config) {
    _requireDeveloper();
    return FilePicker.saveFile(
        dialogTitle: 'Save grading template',
        fileName: fileName(config),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(encode(config))));
  }

  /// Sends the file to another app (Drive, email, chat).
  static Future<void> share(TemplateCalibration config) async {
    _requireDeveloper();
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(utf8.encode(encode(config))),
          mimeType: 'application/json', name: fileName(config))
    ], fileNameOverrides: [
      fileName(config)
    ], subject: 'CheckMate grading template: ${config.name}');
  }

  /// Lets the user pick a `.json` file. Returns null when cancelled.
  static Future<TemplateCalibration?> open() async {
    _requireDeveloper();
    final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true);
    if (picked == null) return null;
    final file = picked.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    return decode(utf8.decode(bytes, allowMalformed: false));
  }

  static void _requireDeveloper() {
    if (!AppBuild.developerTools) {
      throw StateError('Developer edition required');
    }
  }
}
