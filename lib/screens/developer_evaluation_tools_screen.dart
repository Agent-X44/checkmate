import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_build.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/template_calibration.dart';
import '../services/developer_template_store.dart';
import '../services/image_processor.dart';
import '../services/sheet_evaluation_service.dart';
import 'template_designer_screen.dart';

class DeveloperEvaluationToolsScreen extends StatefulWidget {
  final ProcessedSheet sheet;
  final BubbleSheetTemplate template;
  final Future<List<Map<String, dynamic>>> Function()? loadQuestions;
  const DeveloperEvaluationToolsScreen(
      {super.key,
      required this.sheet,
      required this.template,
      this.loadQuestions});
  @override
  State<DeveloperEvaluationToolsScreen> createState() =>
      _DeveloperEvaluationToolsScreenState();
}

class _DeveloperEvaluationToolsScreenState
    extends State<DeveloperEvaluationToolsScreen> {
  late TemplateCalibration _config;
  late ProcessedSheet _preview;
  final _key = TextEditingController();
  bool _busy = false;
  bool _graded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _config = TemplateCalibration.fromTemplate(widget.template);
    _preview = widget.sheet;
    DeveloperTemplateStore.active(widget.template.id).then((c) {
      if (mounted && c != null) setState(() => _config = c);
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = TemplateCalibration.fromMap(_config.toMap());
      var preview = await ImageProcessor.previewCalibration(
          widget.sheet, widget.template, config);
      List<Map<String, dynamic>>? questions;
      if (widget.loadQuestions != null) {
        questions = await widget.loadQuestions!();
      } else if (_key.text.trim().isNotEmpty) {
        final answers =
            _key.text.trim().toUpperCase().split(RegExp(r'[\s,;]+'));
        questions = [
          for (var i = 0; i < answers.length; i++)
            {
              'question_type':
                  widget.template.tfCount > 0 && i >= widget.template.mcqCount
                      ? 'TF'
                      : 'MCQ',
              'correct_answer': answers[i],
            }
        ];
      }
      if (questions != null) {
        preview = SheetEvaluationService.evaluate(preview, questions,
            setType: preview.detectedSet ?? 'A');
      }
      if (mounted) {
        setState(() {
          _preview = preview;
          _graded = questions != null;
        });
      }
    } catch (e) {
      debugPrint('Developer preview failed: $e');
      if (mounted) {
        setState(() => _error = e is FormatException
            ? e.message.toString()
            : 'Could not process this preview. Check the template and image.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _design() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => TemplateDesignerScreen(
                imageBytes: widget.sheet.warpedImage,
                initialBubbles: _config.answerBubbles,
                initialAnswerRegions: _config.answerRegions,
                initialQrRegion: _config.qrRegion,
                initialSetRegion: _config.setRegion,
                initialSetBubbles: _config.setBubbles,
                onApply: (bubbles, boxes, qr, set, sets) {
                  setState(() => _config = _config.copyWith(
                      answerBubbles: bubbles,
                      answerRegions: boxes,
                      qrRegion: qr,
                      setRegion: set,
                      setBubbles: sets));
                })));
  }

  Future<void> _save() async {
    final controller = TextEditingController(text: _config.name);
    final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Save local template'),
                content: TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(labelText: 'Template name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Save'))
                ]));
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final config = _config.copyWith(name: name);
      await DeveloperTemplateStore.save(config);
      if (mounted) {
        setState(() => _config = config);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Template saved on this device. Used for the next matching developer scan.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _transfer(String action) async {
    if (action == 'reset') {
      setState(
          () => _config = TemplateCalibration.fromTemplate(widget.template));
      return;
    }
    if (action == 'load') {
      final profiles = (await DeveloperTemplateStore.load())
          .where((c) => c.baseTemplateId == widget.template.id)
          .toList();
      if (!mounted) return;
      final selected = await showDialog<TemplateCalibration>(
          context: context,
          builder: (context) => SimpleDialog(
              title: const Text('Local templates'),
              children: profiles.isEmpty
                  ? [
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No saved templates for this layout.'))
                    ]
                  : profiles
                      .map((p) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, p),
                          child: Text(p.name)))
                      .toList()));
      if (selected != null && mounted) setState(() => _config = selected);
      return;
    }
    final controller = TextEditingController(
        text: action == 'export'
            ? const JsonEncoder.withIndent('  ').convert(_config.toMap())
            : '');
    final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(action == 'export'
                    ? 'Export template JSON'
                    : 'Import template JSON'),
                content: SizedBox(
                    width: 650,
                    child: TextField(
                        controller: controller,
                        readOnly: action == 'export',
                        maxLines: 12,
                        decoration: const InputDecoration(
                            hintText: 'Paste template JSON'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close')),
                  FilledButton(
                      onPressed: () async {
                        if (action == 'export') {
                          await Clipboard.setData(
                              ClipboardData(text: controller.text));
                        }
                        if (context.mounted) {
                          Navigator.pop(context, controller.text);
                        }
                      },
                      child: Text(action == 'export' ? 'Copy JSON' : 'Import'))
                ]));
    controller.dispose();
    if (text == null || action == 'export' || !mounted) return;
    try {
      final config = TemplateCalibration.fromMap(
          Map<String, dynamic>.from(jsonDecode(text)));
      if (config.baseTemplateId != widget.template.id) {
        throw const FormatException(
            'Choose the matching base layout before importing');
      }
      setState(() => _config = config);
    } catch (e) {
      setState(() => _error = e is FormatException
          ? e.message.toString()
          : 'Invalid template JSON');
    }
  }

  Widget _slider(String name, double value, double min, double max,
          void Function(double) change) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$name: ${value.toStringAsFixed(3)}'),
        Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: _busy ? null : (v) => setState(() => change(v)))
      ]);
  Widget _image(Uint8List bytes) => bytes.isEmpty
      ? const Center(child: Text('Run a preview to inspect this image.'))
      : InteractiveViewer(
          maxScale: 12,
          child: Image.memory(bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, e, s) => const Text('Image unavailable')));
  @override
  Widget build(BuildContext context) {
    if (!AppBuild.developerTools) {
      return const Scaffold(
          body: Center(child: Text('Developer edition required')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Evaluation Dev Tools'), actions: [
          PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: _transfer,
              itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'load', child: Text('Load local template')),
                    PopupMenuItem(value: 'import', child: Text('Import JSON')),
                    PopupMenuItem(value: 'export', child: Text('Export JSON')),
                    PopupMenuItem(
                        value: 'reset', child: Text('Reset adjustments'))
                  ])
        ]),
        body: DefaultTabController(
            length: 5,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Text('${_config.name} • Local test preview'),
                    const Text(
                        'Template tests stay on this device and do not change saved course results.'),
                    if (_graded)
                      Text(
                          'Test score: ${_preview.results.where((r) => r.isCorrect == true).length} / ${_preview.results.length}'),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
              const TabBar(isScrollable: true, tabs: [
                Tab(text: 'ADJUST'),
                Tab(text: 'IMAGE'),
                Tab(text: 'THRESHOLD'),
                Tab(text: 'ANSWER REGION'),
                Tab(text: 'ITEMS')
              ]),
              Expanded(
                  child: TabBarView(children: [
                ListView(padding: const EdgeInsets.all(16), children: [
                  if (widget.loadQuestions == null)
                    TextField(
                        controller: _key,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Optional test answer key',
                            hintText: 'A B C D …; TRUE/FALSE for TF rows')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _design,
                      icon: const Icon(Icons.design_services),
                      label: const Text(
                          'Create / edit template regions and bubbles')),
                  _slider('Grid start', _config.gridStart, 0, 1,
                      (v) => _config = _config.copyWith(gridStart: v)),
                  _slider('Grid width', _config.gridWidth, .01, 1,
                      (v) => _config = _config.copyWith(gridWidth: v)),
                  _slider('Horizontal region offset', _config.xOffset, -.5, .5,
                      (v) => _config = _config.copyWith(xOffset: v)),
                  _slider(
                      'Vertical row offset (pixels)',
                      _config.yOffset.toDouble(),
                      -200,
                      200,
                      (v) => _config = _config.copyWith(yOffset: v.round())),
                  _slider('Row spacing (pixels)', _config.rowSpacing, -10, 10,
                      (v) => _config = _config.copyWith(rowSpacing: v)),
                  _slider('Strip height', _config.stripHeight, .3, 3,
                      (v) => _config = _config.copyWith(stripHeight: v)),
                  _slider('Ink fill threshold', _config.fillThreshold, .01, .9,
                      (v) => _config = _config.copyWith(fillThreshold: v)),
                  _slider('Sample zone width', _config.zoneWidth, .1, 1,
                      (v) => _config = _config.copyWith(zoneWidth: v)),
                  _slider('Sample zone height', _config.zoneHeight, .1, 1,
                      (v) => _config = _config.copyWith(zoneHeight: v)),
                  _slider(
                      'Manual bubble sample radius',
                      _config.bubbleRadius,
                      .001,
                      .03,
                      (v) => _config = _config.copyWith(bubbleRadius: v)),
                  Text(
                      'Manual bubbles: ${_config.answerBubbles.length}. Place in question order, A to D (A to B for TF).'),
                ]),
                _image(_preview.warpedImage),
                _image(_preview.thresholdImage),
                _image(_preview.answerRegion),
                ListView.builder(
                    itemCount: _preview.results.length,
                    itemBuilder: (_, i) {
                      final r = _preview.results[i];
                      return ListTile(
                          title: Text(
                              'Q${i + 1}: ${r.isAmbiguous ? r.multipleAnswers.join(', ') : r.answer ?? 'None'}'),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Confidence: ${r.confidence.toStringAsFixed(3)}${r.isAmbiguous ? ' • Ambiguous' : ''}'),
                                if (i < _preview.questionImages.length)
                                  Image.memory(_preview.questionImages[i],
                                      height: 65, fit: BoxFit.contain)
                              ]));
                    }),
              ])),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(spacing: 12, runSpacing: 8, children: [
                        FilledButton.icon(
                            onPressed: _busy ? null : _run,
                            icon: const Icon(Icons.science),
                            label: Text(
                                _busy ? 'Testing...' : 'Test adjustments')),
                        OutlinedButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save local template')),
                      ]))),
              if (_busy) const LinearProgressIndicator(),
            ])));
  }
}
