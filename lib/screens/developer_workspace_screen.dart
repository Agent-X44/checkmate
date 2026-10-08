import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../config/app_build.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/template_registry.dart';
import '../services/developer_template_store.dart';
import '../services/image_processor.dart';
import 'developer_evaluation_tools_screen.dart';
import 'root_auth_wrapper.dart';
import 'answer_sheet_design_screen.dart';
import 'scanner_screen.dart';

class DeveloperWorkspaceScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;
  const DeveloperWorkspaceScreen(
      {super.key, required this.themeMode, required this.onThemeChanged});
  @override
  State<DeveloperWorkspaceScreen> createState() =>
      _DeveloperWorkspaceScreenState();
}

class _DeveloperWorkspaceScreenState extends State<DeveloperWorkspaceScreen> {
  BubbleSheetTemplate _template = AnswerSheetTemplateRegistry.all.first;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }

  Future<void> _open(Uint8List bytes, {bool align = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final calibration = await DeveloperTemplateStore.active(_template.id);
      final sheet = align
          ? await ImageProcessor.processOmr(OmrRequest(
              bytes: bytes,
              corners: const [],
              template: _template,
              calibration: calibration,
              developerSandbox: true))
          : ProcessedSheet(
              warpedImage: bytes,
              thresholdImage: Uint8List(0),
              answerRegion: Uint8List(0),
              questionImages: [],
              results: [],
              templateName: _template.name,
              questionCapacity: _template.totalQuestions);
      if (sheet == null) {
        throw const FormatException('Could not process this photo');
      }
      if (!mounted) return;
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => DeveloperEvaluationToolsScreen(
                  sheet: sheet, template: _template)));
    } catch (e) {
      debugPrint('Developer image failed: $e');
      if (mounted) {
        setState(() => _error = e is SheetAlignmentException
            ? e.toString()
            : 'Could not open this image. Try a cropped image or keep all four corner marks visible.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick({required bool align}) async {
    final file = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true);
    if (file == null || !mounted) return;
    final selected = file.files.single;
    final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
    if (mounted) await _open(bytes, align: align);
  }

  Future<void> _camera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (context) => ScannerScreen(
                  cameras: cameras,
                  isActive: true,
                  developerSandbox: true,
                  sandboxTemplate: _template,
                  onClose: () => Navigator.pop(context))));
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Camera unavailable. You can still open photos.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppBuild.developerTools) {
      return const Scaffold(
          body: Center(child: Text('Developer edition required')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('CheckMate Dev • Offline workspace')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  const Text('Scan, inspect and build templates',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'No account or internet connection needed. Images, test grades and template presets stay on this device.'),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<BubbleSheetTemplate>(
                      initialValue: _template,
                      decoration: const InputDecoration(
                          labelText: 'Base answer-sheet layout'),
                      items: AnswerSheetTemplateRegistry.all
                          .map((t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)))
                          .toList(),
                      onChanged:
                          _busy ? null : (t) => setState(() => _template = t!)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                      onPressed: _busy ? null : _camera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Scan test sheet')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(align: true),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Open sheet photo • align corners')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(align: false),
                      icon: const Icon(Icons.crop),
                      label: const Text('Design from cropped image')),
                  OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final asset =
                                  await rootBundle.load(_template.assetPath);
                              if (mounted) {
                                await _open(asset.buffer.asUint8List(),
                                    align: true);
                              }
                            },
                      icon: const Icon(Icons.science),
                      label: const Text('Use sample template')),
                  OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AnswerSheetDesignScreen(
                                      courseId: '', offlineSandbox: true))),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text(
                          'PDF layout tools • print local test sheet')),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 32),
                  const Divider(),
                  const Text(
                      'Optional: sign in to use real courses and assessments.'),
                  TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => RootAuthWrapper(
                                      themeMode: widget.themeMode,
                                      onThemeChanged: widget.onThemeChanged))),
                      icon: const Icon(Icons.login),
                      label: const Text('Open LMS sign-in')),
                ]))));
  }
}
