import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../config/app_build.dart';
import '../models/omr/bubble_grid_anchors.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/template_calibration.dart';
import '../widgets/sheet_overlay_view.dart';

/// Developer tool: place a grading template by dragging four anchor handles
/// per answer column onto printed bubbles. Every bubble is interpolated from
/// them and previewed live against the sheet's threshold image. Returns the
/// updated [TemplateCalibration] (manual bubbles + size + threshold).
class GradingTemplateBuilderScreen extends StatefulWidget {
  final ProcessedSheet sheet;
  final BubbleSheetTemplate template;
  final TemplateCalibration config;

  const GradingTemplateBuilderScreen(
      {super.key,
      required this.sheet,
      required this.template,
      required this.config});

  @override
  State<GradingTemplateBuilderScreen> createState() =>
      _GradingTemplateBuilderScreenState();
}

class _Ink {
  final Uint8List rgba;
  final int width, height;
  const _Ink(this.rgba, this.width, this.height);
}

class _GradingTemplateBuilderScreenState
    extends State<GradingTemplateBuilderScreen> {
  static const _handleColors = [
    Color(0xFFFF4081),
    Color(0xFFFFAB00),
    Color(0xFF7C4DFF),
    Color(0xFF00E676),
  ];

  final _view = TransformationController();
  late List<ColumnAnchors> _columns;
  late double _radius = widget.config.bubbleRadius;
  late double _threshold = widget.config.fillThreshold;
  int _column = 0;
  int _handle = 0;
  bool _coarse = false;
  bool _dragging = false;
  ui.Image? _image;
  _Ink? _ink;
  String? _error;

  int get _choices => widget.template.choicesPerQuestion;
  List<Rect> get _regions => widget.config.answerRegions;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    final n = _regions.length;
    _columns = (widget.config.answerBubbles.isEmpty
            ? null
            : BubbleGridAnchors.fromBubbles(
                t, n, widget.config.answerBubbles)) ??
        BubbleGridAnchors.fromZones(t, n, widget.sheet.bubbleZones) ??
        BubbleGridAnchors.fromRegions(t, _regions);
    _view.addListener(_onZoom);
    _load();
  }

  void _onZoom() => setState(() {});

  Future<void> _load() async {
    try {
      final image = await decodeImageFromList(widget.sheet.warpedImage);
      _Ink? ink;
      if (widget.sheet.thresholdImage.isNotEmpty) {
        final t = await decodeImageFromList(widget.sheet.thresholdImage);
        final data = await t.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null) {
          ink = _Ink(data.buffer.asUint8List(), t.width, t.height);
        }
        t.dispose();
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _ink = ink;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this sheet image.');
    }
  }

  @override
  void dispose() {
    _view.removeListener(_onZoom);
    _view.dispose();
    _image?.dispose();
    super.dispose();
  }

  List<Offset> get _bubbles =>
      BubbleGridAnchors.generate(widget.template, _columns);

  /// Ink ratio per bubble, sampled the same way as the native reader
  /// (square of side 2r around the centre). The threshold JPEG differs from
  /// the in-memory mask by compression only, so this is a close preview;
  /// "Test" in the dev tools runs the real reader.
  double _fill(Offset p) {
    final ink = _ink;
    if (ink == null) return 0;
    final w = ink.width, h = ink.height;
    final r = (w * _radius).round().clamp(1, w);
    final left = (p.dx * w - r).round().clamp(0, w - 1);
    final top = (p.dy * h - r).round().clamp(0, h - 1);
    final cw = (r * 2).clamp(1, w - left), ch = (r * 2).clamp(1, h - top);
    var on = 0;
    for (var y = top; y < top + ch; y++) {
      var i = (y * w + left) * 4;
      for (var x = 0; x < cw; x++, i += 4) {
        if (ink.rgba[i] > 127) on++;
      }
    }
    return on / (cw * ch);
  }

  void _move(int column, int handle, Offset delta) {
    setState(() {
      final a = _columns[column];
      final p = a.points[handle] + delta;
      _columns[column] = a.withPoint(
          handle, Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)));
    });
  }

  void _nudge(Offset direction) {
    final image = _image;
    if (image == null) return;
    final step = _coarse ? 5.0 : 1.0;
    _move(
        _column,
        _handle,
        Offset(direction.dx * step / image.width,
            direction.dy * step / image.height));
  }

  void _shiftColumn(Offset direction) {
    final image = _image;
    if (image == null) return;
    final step = _coarse ? 5.0 : 1.0;
    setState(() => _columns[_column] = _columns[_column].shifted(Offset(
        direction.dx * step / image.width,
        direction.dy * step / image.height)));
  }

  void _reset() => setState(() => _columns = BubbleGridAnchors.fromZones(
          widget.template, _regions.length, widget.sheet.bubbleZones) ??
      BubbleGridAnchors.fromRegions(widget.template, _regions));

  void _apply() {
    try {
      final config = TemplateCalibration.fromMap(widget.config
          .copyWith(
              answerBubbles: _bubbles,
              bubbleRadius: _radius,
              fillThreshold: _threshold)
          .toMap());
      Navigator.pop(context, config);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  String _handleName(int i) {
    final last = String.fromCharCode(64 + _choices);
    return const ['First row ', 'First row ', 'Last row ', 'Last row '][i] +
        (i.isEven ? 'A' : last);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppBuild.developerTools) {
      return const Scaffold(
          body: Center(child: Text('Developer edition required')));
    }
    final image = _image;
    final bubbles = _bubbles;
    final fills = [for (final p in bubbles) _fill(p)];
    var marked = 0, ambiguous = 0, offset = 0;
    for (var q = 0; q < widget.template.totalQuestions; q++) {
      final n = BubbleGridAnchors.choicesFor(widget.template, q);
      final count = fills
          .sublist(offset, math.min(offset + n, fills.length))
          .where((f) => f > _threshold)
          .length;
      if (count == 1) marked++;
      if (count > 1) ambiguous++;
      offset += n;
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Grading Template Builder'), actions: [
        IconButton(
            tooltip: 'Reset to the detected grid',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset),
      ]),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: scheme.surfaceContainer,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text(
              'Drag the four colored handles onto the centres of the printed '
              'bubbles they name. Pinch to zoom. Bubbles turn blue on ink.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: _error != null && image == null
              ? Center(child: Text(_error!))
              : image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (context, box) {
                      final width = box.maxWidth;
                      final size =
                          Size(width, width * image.height / image.width);
                      final zoom = _view.value.getMaxScaleOnAxis();
                      final handle = 30 / zoom;
                      return InteractiveViewer(
                        transformationController: _view,
                        constrained: false,
                        minScale: 1,
                        maxScale: 10,
                        panEnabled: !_dragging,
                        scaleEnabled: !_dragging,
                        child: SizedBox.fromSize(
                          size: size,
                          child: Stack(clipBehavior: Clip.none, children: [
                            Positioned.fill(
                                child: CustomPaint(
                                    painter: _BuilderPainter(
                                        image: image,
                                        columns: _columns,
                                        bubbles: bubbles,
                                        fills: fills,
                                        threshold: _threshold,
                                        radius: _radius,
                                        zoom: zoom,
                                        selectedColumn: _column))),
                            for (var c = 0; c < _columns.length; c++)
                              for (var h = 0; h < 4; h++)
                                Positioned(
                                  left: _columns[c].points[h].dx * size.width -
                                      handle / 2,
                                  top: _columns[c].points[h].dy * size.height -
                                      handle / 2,
                                  width: handle,
                                  height: handle,
                                  child: GestureDetector(
                                    key: ValueKey('anchor-$c-$h'),
                                    // Track from touch-down so the handle stays
                                    // under the finger instead of lagging by
                                    // the drag slop.
                                    dragStartBehavior: DragStartBehavior.down,
                                    behavior: HitTestBehavior.opaque,
                                    onPanDown: (_) => setState(() {
                                      _dragging = true;
                                      _column = c;
                                      _handle = h;
                                    }),
                                    onPanUpdate: (d) => _move(
                                        c,
                                        h,
                                        Offset(d.delta.dx / size.width,
                                            d.delta.dy / size.height)),
                                    onPanEnd: (_) =>
                                        setState(() => _dragging = false),
                                    onPanCancel: () =>
                                        setState(() => _dragging = false),
                                    child: CustomPaint(
                                        painter: _HandlePainter(
                                            _handleColors[h],
                                            selected:
                                                c == _column && h == _handle,
                                            dimmed: c != _column)),
                                  ),
                                ),
                          ]),
                        ),
                      );
                    }),
        ),
        _controls(marked, ambiguous),
      ]),
    );
  }

  Widget _controls(int marked, int ambiguous) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.template.totalQuestions;
    Widget pad(void Function(Offset) action, String label) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_left),
                  onPressed: () => action(const Offset(-1, 0))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_up),
                    onPressed: () => action(const Offset(0, -1))),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () => action(const Offset(0, 1))),
              ]),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_right),
                  onPressed: () => action(const Offset(1, 0))),
            ]),
          ],
        );
    return SafeArea(
      top: false,
      child: Container(
        color: scheme.surfaceContainer,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_columns.length > 1)
            Wrap(spacing: 8, children: [
              for (var i = 0; i < _columns.length; i++)
                ChoiceChip(
                    label: Text('Column ${i + 1}'),
                    selected: _column == i,
                    onSelected: (_) => setState(() => _column = i)),
            ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (var h = 0; h < 4; h++)
              ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: _handleColors[h]),
                  label: Text(_handleName(h)),
                  selected: _handle == h,
                  onSelected: (_) => setState(() => _handle = h)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            pad(_nudge, 'Selected handle'),
            pad(_shiftColumn, 'Whole column'),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Step'),
              Switch(
                  value: _coarse,
                  onChanged: (v) => setState(() => _coarse = v)),
              Text(_coarse ? '5 px' : '1 px'),
            ]),
          ]),
          _slider('Bubble size', _radius, .002, .03,
              (v) => setState(() => _radius = v), 3),
          _slider('Fill threshold', _threshold, .01, .9,
              (v) => setState(() => _threshold = v), 2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
                _ink == null
                    ? 'Run a preview in the dev tools to see live ink fill.'
                    : 'Live preview: $marked of $total answered'
                        '${ambiguous > 0 ? ' • $ambiguous ambiguous' : ''}',
                style: TextStyle(
                    color: ambiguous > 0 ? Colors.orange : null,
                    fontWeight: FontWeight.w600)),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: scheme.error)),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary),
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('USE THIS TEMPLATE')),
          ),
        ]),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
          void Function(double) change, int digits) =>
      Row(children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
            child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: change)),
        SizedBox(
            width: 48,
            child:
                Text(value.toStringAsFixed(digits), textAlign: TextAlign.end)),
      ]);
}

class _BuilderPainter extends CustomPainter {
  final ui.Image image;
  final List<ColumnAnchors> columns;
  final List<Offset> bubbles;
  final List<double> fills;
  final double threshold, radius, zoom;
  final int selectedColumn;

  _BuilderPainter(
      {required this.image,
      required this.columns,
      required this.bubbles,
      required this.fills,
      required this.threshold,
      required this.radius,
      required this.zoom,
      required this.selectedColumn});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
    final line = 1.5 / zoom;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    for (var c = 0; c < columns.length; c++) {
      final a = columns[c];
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..color = SheetOverlayColors.region
            .withValues(alpha: c == selectedColumn ? .9 : .4);
      canvas.drawPath(
          Path()
            ..moveTo(at(a.firstA).dx, at(a.firstA).dy)
            ..lineTo(at(a.firstLast).dx, at(a.firstLast).dy)
            ..lineTo(at(a.lastLast).dx, at(a.lastLast).dy)
            ..lineTo(at(a.lastA).dx, at(a.lastA).dy)
            ..close(),
          edge);
    }
    final r = radius * size.width;
    for (var i = 0; i < bubbles.length; i++) {
      final on = fills[i] > threshold;
      final color = on ? SheetOverlayColors.detected : SheetOverlayColors.empty;
      final centre = at(bubbles[i]);
      canvas.drawCircle(
          centre, r, Paint()..color = color.withValues(alpha: on ? .4 : .12));
      canvas.drawCircle(
          centre,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = line
            ..color = color);
    }
  }

  @override
  bool shouldRepaint(_BuilderPainter old) => true;
}

class _HandlePainter extends CustomPainter {
  final Color color;
  final bool selected, dimmed;
  _HandlePainter(this.color, {required this.selected, required this.dimmed});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * (selected ? .22 : .14)
      ..color = color.withValues(alpha: dimmed ? .45 : 1);
    // Hollow ring with a crosshair keeps the printed bubble visible.
    canvas.drawCircle(c, r * .8, paint);
    canvas.drawLine(c - Offset(r * .35, 0), c + Offset(r * .35, 0), paint);
    canvas.drawLine(c - Offset(0, r * .35), c + Offset(0, r * .35), paint);
  }

  @override
  bool shouldRepaint(_HandlePainter old) =>
      old.color != color || old.selected != selected || old.dimmed != dimmed;
}
