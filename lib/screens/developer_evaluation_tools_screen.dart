import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_build.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/template_calibration.dart';
import '../services/developer_template_store.dart';
import '../services/image_processor.dart';
import '../services/sheet_evaluation_service.dart';
import '../widgets/sheet_overlay_view.dart';
import 'grading_template_builder_screen.dart';
import 'template_designer_screen.dart';
import '../services/template_file_service.dart';

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
  bool _rerun = false;
  bool _showAlignment = true;
  int _column = 0;
  Timer? _debounce;
  String? _error;

  /// Saved template developer scans use for this layout; null = built-in.
  String? _scanTemplate;
  @override
  void initState() {
    super.initState();
    _config = TemplateCalibration.fromTemplate(widget.template);
    _preview = widget.sheet;
    DeveloperTemplateStore.active(widget.template.id).then((c) {
      if (!mounted) return;
      if (c != null) {
        setState(() {
          _config = c;
          _scanTemplate = c.name;
        });
      }
      _run();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _key.dispose();
    super.dispose();
  }

  /// Re-grades shortly after the last adjustment so the overlay follows the
  /// sliders without queueing a preview for every drag frame.
  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  void _adjust(TemplateCalibration config) {
    setState(() => _config = config);
    _schedulePreview();
  }

  Future<void> _run() async {
    if (_busy) {
      _rerun = true;
      return;
    }
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
      if (_rerun && mounted) {
        _rerun = false;
        unawaited(_run());
      }
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
                  _schedulePreview();
                })));
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshScanTemplate() async {
    final active = await DeveloperTemplateStore.active(widget.template.id);
    if (mounted) setState(() => _scanTemplate = active?.name);
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
      setState(() {
        _config = config;
        _scanTemplate = name;
      });
      _notify('Saved on this device and selected for developer scans.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Loads an imported template into the editor when it is for this layout;
  /// otherwise keeps it as a saved template for its own layout.
  Future<void> _receive(TemplateCalibration config, String source) async {
    if (config.baseTemplateId == widget.template.id) {
      _adjust(config);
      _notify('$source "${config.name}". Previewing now; tap Save to use it '
          'for scans.');
      return;
    }
    await DeveloperTemplateStore.save(config, activate: false);
    _notify('"${config.name}" is for layout ${config.baseTemplateId}. Saved '
        'it under Saved templates for that layout.');
  }

  Future<void> _menu(String action) async {
    try {
      switch (action) {
        case 'design':
          await _design();
        case 'save':
          await _save();
        case 'templates':
          await _templates();
        case 'builtin':
          _adjust(TemplateCalibration.fromTemplate(widget.template));
          await DeveloperTemplateStore.setActive(widget.template.id, null);
          await _refreshScanTemplate();
          _notify('Using the built-in template for previews and scans.');
        case 'open_file':
          final config = await TemplateFileService.open();
          if (config != null) await _receive(config, 'Imported');
        case 'save_file':
          final path = await TemplateFileService.save(_config);
          if (path != null) {
            _notify('Saved ${TemplateFileService.fileName(_config)}');
          }
        case 'share_file':
          await TemplateFileService.share(_config);
        case 'copy':
          await Clipboard.setData(
              ClipboardData(text: TemplateFileService.encode(_config)));
          _notify('Template JSON copied.');
        case 'paste':
          final text = await _pasteDialog();
          if (text != null && text.trim().isNotEmpty) {
            await _receive(TemplateFileService.decode(text), 'Pasted');
          }
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = 'Template not imported: ${e.message}');
      }
    } catch (e) {
      debugPrint('Template action $action failed: $e');
      if (mounted) setState(() => _error = 'Could not complete that action.');
    }
  }

  Future<String?> _pasteDialog() async {
    final controller = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    controller.text = clip?.text ?? '';
    if (!mounted) return null;
    final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Paste template JSON'),
                content: SizedBox(
                    width: 650,
                    child: TextField(
                        controller: controller,
                        maxLines: 12,
                        decoration: const InputDecoration(
                            hintText: 'Paste template JSON'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Import'))
                ]));
    controller.dispose();
    return text;
  }

  /// Built-in plus saved templates for this layout: tap to edit, the radio
  /// chooses what developer scans use, the bin deletes.
  Future<void> _templates() async {
    var rows = (await DeveloperTemplateStore.load())
        .where((c) => c.baseTemplateId == widget.template.id)
        .toList();
    String? active = _scanTemplate;
    if (!mounted) return;
    final chosen = await showDialog<TemplateCalibration>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              Future<void> select(String? name) async {
                await DeveloperTemplateStore.setActive(
                    widget.template.id, name);
                update(() => active = name);
              }

              Widget tile(TemplateCalibration config, String? name,
                      {bool builtIn = false}) =>
                  ListTile(
                    leading: Radio<String?>(value: name, toggleable: false),
                    title: Text(
                        builtIn ? 'Built-in: ${config.name}' : config.name),
                    subtitle: Text(config.answerBubbles.isEmpty
                        ? 'Automatic grid'
                        : '${config.answerBubbles.length} bubbles'),
                    onTap: () => Navigator.pop(context, config),
                    trailing: builtIn
                        ? null
                        : IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await DeveloperTemplateStore.delete(
                                  widget.template.id, config.name);
                              final remaining =
                                  (await DeveloperTemplateStore.load())
                                      .where((c) =>
                                          c.baseTemplateId ==
                                          widget.template.id)
                                      .toList();
                              update(() {
                                rows = remaining;
                                if (active == config.name) active = null;
                              });
                            }),
                  );

              return AlertDialog(
                title: const Text('Grading templates'),
                content: SizedBox(
                  width: 520,
                  child: RadioGroup<String?>(
                    groupValue: active,
                    onChanged: select,
                    child: ListView(shrinkWrap: true, children: [
                      const Text(
                          'The selected circle is used for developer scans. Tap '
                          'a name to load it into the editor.'),
                      tile(TemplateCalibration.fromTemplate(widget.template),
                          null,
                          builtIn: true),
                      for (final row in rows) tile(row, row.name),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              );
            }));
    await _refreshScanTemplate();
    if (chosen != null && mounted) _adjust(chosen);
  }

  Widget _section(String title) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(title,
          style: const TextStyle(
              color: SheetOverlayColors.region,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: .4)));

  Widget _slider(String name, double value, double min, double max,
      TemplateCalibration Function(double) change,
      {int digits = 2}) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(children: [
      SizedBox(
          width: 104,
          child: Text(name,
              style: const TextStyle(fontSize: 12, color: Colors.white70))),
      Expanded(
          child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  thumbColor: accent,
                  inactiveTrackColor: Colors.white24,
                  trackHeight: 4,
                  overlayShape: SliderComponentShape.noOverlay),
              child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: (v) => _adjust(change(v))))),
      SizedBox(
          width: 52,
          child: Text(value.toStringAsFixed(digits),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Colors.white70))),
    ]);
  }

  /// Builds the next config with the selected column changed, clamped to the
  /// page so a preset always stays importable.
  TemplateCalibration _withColumn(Rect Function(Rect) change) {
    final regions = List.of(_config.answerRegions);
    final column = _column.clamp(0, regions.length - 1);
    final r = change(regions[column]);
    final width = r.width.clamp(.02, 1.0);
    final height = r.height.clamp(.02, 1.0);
    regions[column] = Rect.fromLTWH(r.left.clamp(0.0, 1 - width),
        r.top.clamp(0.0, 1 - height), width, height);
    return _config.copyWith(answerRegions: regions);
  }

  Future<void> _openBuilder() async {
    // The builder previews ink against the threshold image of a fresh read.
    if (_preview.thresholdImage.isEmpty) await _run();
    if (!mounted) return;
    final result = await Navigator.push<TemplateCalibration>(
        context,
        MaterialPageRoute(
            builder: (_) => GradingTemplateBuilderScreen(
                sheet: _preview, template: widget.template, config: _config)));
    if (result != null && mounted) _adjust(result);
  }

  Widget _gridSliders() {
    final column = _column.clamp(0, _config.answerRegions.length - 1);
    final region = _config.answerRegions[column];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_config.answerBubbles.isNotEmpty)
        const Text(
            'Ignored for grading while a bubble template is in use. Column '
            'boxes still set the builder\'s starting position.',
            style: TextStyle(fontSize: 12, color: Colors.orange)),
      _section('COLUMN BOUNDING BOXES'),
      if (_config.answerRegions.length > 1)
        Wrap(spacing: 8, children: [
          for (var i = 0; i < _config.answerRegions.length; i++)
            ChoiceChip(
                label: Text('Col ${i + 1}'),
                selected: column == i,
                onSelected: (_) => setState(() => _column = i)),
        ]),
      _slider('Col${column + 1} X', region.left, 0, 1,
          (v) => _withColumn((r) => r.translate(v - r.left, 0))),
      _slider('Col${column + 1} Y', region.top, 0, 1,
          (v) => _withColumn((r) => r.translate(0, v - r.top))),
      _slider('Col width', region.width, .02, 1,
          (v) => _withColumn((r) => Rect.fromLTWH(r.left, r.top, v, r.height))),
      _slider('Col height', region.height, .02, 1,
          (v) => _withColumn((r) => Rect.fromLTWH(r.left, r.top, r.width, v))),
      _section('ROW & GRID'),
      _slider('Y-offset (px)', _config.yOffset.toDouble(), -200, 200,
          (v) => _config.copyWith(yOffset: v.round()),
          digits: 0),
      _slider('Row spacing', _config.rowSpacing, -10, 10,
          (v) => _config.copyWith(rowSpacing: v)),
      _slider('Strip height', _config.stripHeight, .3, 3,
          (v) => _config.copyWith(stripHeight: v)),
      _slider('X-offset', _config.xOffset, -.5, .5,
          (v) => _config.copyWith(xOffset: v)),
      _slider(
          'Grid start',
          _config.gridStart,
          -.5,
          1,
          (v) => _config.copyWith(
              gridStart: v.clamp(-.5, 1.5 - _config.gridWidth))),
      _slider(
          'Grid width',
          _config.gridWidth,
          .01,
          2,
          (v) => _config.copyWith(
              gridWidth: v.clamp(.01, 1.5 - _config.gridStart))),
      _slider('Zone width', _config.zoneWidth, .1, 1,
          (v) => _config.copyWith(zoneWidth: v)),
      _slider('Zone height', _config.zoneHeight, .1, 1,
          (v) => _config.copyWith(zoneHeight: v)),
    ]);
  }

  Widget _alignmentPanel() {
    final scheme = Theme.of(context).colorScheme;
    final manual = _config.answerBubbles.isNotEmpty;
    return Container(
      color: Colors.black,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .38),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Text('GRADING TEMPLATE',
                style: TextStyle(
                    color: scheme.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 6),
            Text(
                manual
                    ? 'Bubble template: ${_config.answerBubbles.length} '
                        'bubbles placed from anchors. Grading samples exactly '
                        'these positions.'
                    : 'Using the automatic grid. Build a bubble template to '
                        'place every bubble by dragging four handles per '
                        'column.',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary),
                onPressed: _busy ? null : _openBuilder,
                icon: const Icon(Icons.open_with),
                label: Text(manual
                    ? 'Adjust bubble template'
                    : 'Build bubble template')),
            if (manual)
              TextButton.icon(
                  onPressed: () =>
                      _adjust(_config.copyWith(answerBubbles: const [])),
                  icon: const Icon(Icons.grid_off, color: Colors.white70),
                  label: const Text('Remove bubble template (use grid)',
                      style: TextStyle(color: Colors.white70))),
            _slider('Fill threshold', _config.fillThreshold, .01, .9,
                (v) => _config.copyWith(fillThreshold: v)),
            if (manual)
              _slider('Bubble size', _config.bubbleRadius, .002, .03,
                  (v) => _config.copyWith(bubbleRadius: v),
                  digits: 3),
            if (widget.loadQuestions == null) ...[
              _section('TEST ANSWER KEY'),
              TextField(
                  controller: _key,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => _schedulePreview(),
                  decoration: const InputDecoration(
                      hintText: 'A B C D ...; TRUE/FALSE for TF rows',
                      hintStyle: TextStyle(color: Colors.white38))),
            ],
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white70,
                  title: const Text('Advanced: automatic grid sliders',
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                  children: [_gridSliders()]),
            ),
          ]),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final total = _preview.results.length;
    final correct = _preview.results.where((r) => r.isCorrect == true).length;
    final marked = _preview.results.where((r) => r.isFilled).length;
    final flagged = _preview.results.where((r) => r.isAmbiguous).length;
    final percent = total == 0 ? 0.0 : correct * 100 / total;
    final scoreColor = percent >= 75
        ? SheetOverlayColors.correct
        : percent >= 50
            ? Colors.orange
            : SheetOverlayColors.wrong;
    final set = _preview.detectedSet?.replaceFirst('SET ', '');
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(_config.name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold))),
          if (set != null)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.secondary),
                    borderRadius: BorderRadius.circular(16)),
                child: Text('Set $set',
                    style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold))),
        ]),
        Text(
            'Scans use: ${_scanTemplate == null ? 'built-in template' : '"$_scanTemplate"'}'
            ' • local preview, never changes course results',
            style: theme.textTheme.bodySmall),
        const Divider(height: 20),
        Row(children: [
          Expanded(
              child: Text(
                  _graded
                      ? 'Score: $correct / $total'
                      : 'Marked: $marked / $total',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          if (_graded)
            Text('${percent.toStringAsFixed(1)}%',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: scoreColor, fontWeight: FontWeight.bold))
          else if (widget.loadQuestions == null)
            Text('Add a test key to score', style: theme.textTheme.bodySmall),
        ]),
        if (flagged > 0)
          Text('$flagged ambiguous item(s) flagged',
              style: const TextStyle(color: Colors.orange)),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ]),
    );
  }

  Widget _items() => _preview.results.isEmpty
      ? const Center(child: Text('No items read yet. Adjust the alignment.'))
      : ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _preview.results.length,
          separatorBuilder: (_, i) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = _preview.results[i];
            final key = i < _preview.questionDetails.length
                ? _preview.questionDetails[i]['correct_answer']?.toString()
                : null;
            final marked = r.isAmbiguous
                ? r.multipleAnswers.join(', ')
                : r.answer ?? 'None';
            final color = r.isAmbiguous || (key != null && r.isCorrect != true)
                ? SheetOverlayColors.wrong
                : key != null
                    ? SheetOverlayColors.correct
                    : r.isFilled
                        ? SheetOverlayColors.detected
                        : Colors.grey;
            return ListTile(
              dense: true,
              leading: Icon(
                  r.isAmbiguous
                      ? Icons.warning_amber_rounded
                      : key == null
                          ? (r.isFilled
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked)
                          : r.isCorrect == true
                              ? Icons.check_circle
                              : Icons.cancel,
                  color: color),
              title: Text('Q${i + 1}: $marked'),
              subtitle: Text([
                if (key != null) 'Key: $key',
                'Confidence ${r.confidence.toStringAsFixed(3)}',
                if (r.isAmbiguous) 'Ambiguous',
              ].join(' • ')),
              trailing: i < _preview.questionImages.length
                  ? SizedBox(
                      width: 120,
                      child: Image.memory(_preview.questionImages[i],
                          height: 36, fit: BoxFit.contain))
                  : null,
            );
          });

  Widget _overlay({required bool crop}) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: SheetOverlayLegend(graded: _graded)),
        Expanded(
            child: SheetOverlayView(
                sheet: _preview,
                cropToAnswers: crop,
                guideRegions: _config.answerRegions)),
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(title: const Text('Evaluation Dev Tools'), actions: [
          IconButton(
              icon: const Icon(Icons.tune),
              tooltip: _showAlignment
                  ? 'Hide quick alignment'
                  : 'Show quick alignment',
              color: _showAlignment ? scheme.secondary : null,
              onPressed: () =>
                  setState(() => _showAlignment = !_showAlignment)),
          PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'templates',
                        child: ListTile(
                            leading: Icon(Icons.layers_outlined),
                            title: Text('Saved templates…'))),
                    PopupMenuItem(
                        value: 'save',
                        child: ListTile(
                            leading: Icon(Icons.save_outlined),
                            title: Text('Save and use for scans'))),
                    PopupMenuItem(
                        value: 'builtin',
                        child: ListTile(
                            leading: Icon(Icons.restart_alt),
                            title: Text('Use built-in template'))),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'open_file',
                        child: ListTile(
                            leading: Icon(Icons.file_open_outlined),
                            title: Text('Import JSON file…'))),
                    PopupMenuItem(
                        value: 'save_file',
                        child: ListTile(
                            leading: Icon(Icons.file_download_outlined),
                            title: Text('Export JSON file…'))),
                    PopupMenuItem(
                        value: 'share_file',
                        child: ListTile(
                            leading: Icon(Icons.share_outlined),
                            title: Text('Share JSON file…'))),
                    PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                            leading: Icon(Icons.copy),
                            title: Text('Copy JSON'))),
                    PopupMenuItem(
                        value: 'paste',
                        child: ListTile(
                            leading: Icon(Icons.content_paste),
                            title: Text('Paste JSON…'))),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'design',
                        child: ListTile(
                            leading: Icon(Icons.design_services_outlined),
                            title: Text('Edit regions and bubbles'))),
                  ])
        ]),
        body: DefaultTabController(
            length: 4,
            initialIndex: 1,
            child: Column(children: [
              _header(),
              AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _showAlignment
                      ? _alignmentPanel()
                      : const SizedBox(width: double.infinity)),
              SizedBox(
                  height: 2,
                  child: _busy ? const LinearProgressIndicator() : null),
              const TabBar(isScrollable: true, tabs: [
                Tab(text: 'ITEMIZED RESULTS'),
                Tab(text: 'CROPPED IMAGE'),
                Tab(text: 'FULL SHEET'),
                Tab(text: 'THRESHOLD'),
              ]),
              Expanded(
                  child: TabBarView(
                      // Horizontal drags pan the zoomable sheet, not the tabs.
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                    _items(),
                    _overlay(crop: true),
                    _overlay(crop: false),
                    _image(_preview.thresholdImage),
                  ])),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: scheme.secondary,
                                  foregroundColor: scheme.onSecondary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16)),
                              onPressed: _busy ? null : _save,
                              icon: const Icon(Icons.check_circle),
                              label: const Text('SAVE LOCAL TEMPLATE'))))),
            ])));
  }
}
