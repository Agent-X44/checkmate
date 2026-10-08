import 'dart:typed_data';
import 'dart:ui' as ui;
import '../config/app_build.dart';
import 'package:flutter/material.dart';

class TemplateDesignerScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Offset>? initialBubbles;
  final List<Rect>? initialAnswerRegions;
  final Rect? initialQrRegion;
  final Rect? initialSetRegion;
  final List<Offset>? initialSetBubbles;
  final Function(List<Offset> bubbles, List<Rect> answerBoxes, Rect? qrRect,
      Rect? setRect, List<Offset> setBubbles) onApply;

  const TemplateDesignerScreen({
    super.key,
    required this.imageBytes,
    this.initialBubbles,
    this.initialAnswerRegions,
    this.initialQrRegion,
    this.initialSetRegion,
    this.initialSetBubbles,
    required this.onApply,
  });

  @override
  State<TemplateDesignerScreen> createState() => _TemplateDesignerScreenState();
}

class _TemplateDesignerScreenState extends State<TemplateDesignerScreen> {
  late List<BubblePoint> _bubbles;
  late List<Rect> _answerBoxes;
  Rect? _qrRect;
  Rect? _setRect;
  late List<BubblePoint> _setBubbles;
  double _imageAspectRatio = .707;
  List<BubblePoint> get _activeBubbles =>
      _designerMode == 4 ? _setBubbles : _bubbles;
  List<Rect> get _activeRegions => _designerMode == 1
      ? [_qrRect!]
      : _designerMode == 3
          ? [_setRect!]
          : _answerBoxes;
  int _designerMode = 0; // 0: Answer Bubbles, 2: Answer Box
  double _globalRadius = 12.0;

  int? _draggingIndex;
  int? _activeBoxIndex; // For answer boxes
  int? _resizeHandle;

  @override
  void initState() {
    super.initState();
    _bubbles = widget.initialBubbles
            ?.map((p) =>
                BubblePoint(normalizedPosition: p, radius: _globalRadius))
            .toList() ??
        [];

    _qrRect = widget.initialQrRegion ?? const Rect.fromLTRB(.65, .05, .95, .22);
    _setRect =
        widget.initialSetRegion ?? const Rect.fromLTRB(.05, .08, .25, .13);
    _setBubbles = (widget.initialSetBubbles ?? [])
        .map((p) => BubblePoint(normalizedPosition: p, radius: _globalRadius))
        .toList();
    ui.instantiateImageCodec(widget.imageBytes).then((codec) async {
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _imageAspectRatio = ratio);
    }).catchError((Object error) {});

    // Default to ONE column only, as requested
    _answerBoxes = List.from(widget.initialAnswerRegions ??
        [
          const Rect.fromLTRB(0.1, 0.25, 0.9, 0.95),
        ]);
  }

  void _onTapDown(TapDownDetails details, Size size) {
    final pos = details.localPosition;
    final normalizedPos = Offset(pos.dx / size.width, pos.dy / size.height);

    if (_designerMode == 0 || _designerMode == 4) {
      // Answer and set bubbles
      if (!_isNearBubble(_activeBubbles, pos, size)) {
        setState(() => _activeBubbles.add(BubblePoint(
            normalizedPosition: normalizedPos, radius: _globalRadius)));
      }
    }
  }

  bool _isNearBubble(List<BubblePoint> list, Offset pos, Size size) {
    for (var b in list) {
      final bPos = Offset(b.normalizedPosition.dx * size.width,
          b.normalizedPosition.dy * size.height);
      if ((bPos - pos).distance < 25) {
        return true;
      }
    }
    return false;
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    final pos = details.localPosition;

    if (_designerMode == 1 || _designerMode == 2 || _designerMode == 3) {
      for (int i = 0; i < _activeRegions.length; i++) {
        final r = _toPx(_activeRegions[i], size);
        final h = _getHandle(r, pos);
        if (h != null) {
          setState(() {
            _activeBoxIndex = i;
            _resizeHandle = h;
          });
          return;
        }
        if (r.contains(pos)) {
          setState(() {
            _activeBoxIndex = i;
            _resizeHandle = 4;
          });
          return;
        }
      }
    } else if (_designerMode == 0 || _designerMode == 4) {
      for (int i = 0; i < _activeBubbles.length; i++) {
        final bPos = Offset(
            _activeBubbles[i].normalizedPosition.dx * size.width,
            _activeBubbles[i].normalizedPosition.dy * size.height);
        if ((bPos - pos).distance < 20) {
          setState(() => _draggingIndex = i);
          return;
        }
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final delta =
        Offset(details.delta.dx / size.width, details.delta.dy / size.height);
    if ((_designerMode == 1 || _designerMode == 2 || _designerMode == 3) &&
        _activeBoxIndex != null &&
        _activeBoxIndex! >= 0) {
      setState(() {
        final region = _updateRect(_activeRegions[_activeBoxIndex!], delta);
        if (_designerMode == 1) {
          _qrRect = region;
        } else if (_designerMode == 3) {
          _setRect = region;
        } else {
          _answerBoxes[_activeBoxIndex!] = region;
        }
      });
    } else if ((_designerMode == 0 || _designerMode == 4) &&
        _draggingIndex != null) {
      setState(() {
        final point =
            _activeBubbles[_draggingIndex!].normalizedPosition + delta;
        _activeBubbles[_draggingIndex!] = _activeBubbles[_draggingIndex!]
            .copyWith(
                normalizedPosition:
                    Offset(point.dx.clamp(0, 1), point.dy.clamp(0, 1)));
      });
    }
  }

  Rect _toPx(Rect r, Size s) => Rect.fromLTRB(r.left * s.width,
      r.top * s.height, r.right * s.width, r.bottom * s.height);
  int? _getHandle(Rect r, Offset p) {
    final handles = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
    for (int i = 0; i < 4; i++) {
      if ((handles[i] - p).distance < 25) return i;
    }
    return null;
  }

  Rect _updateRect(Rect r, Offset delta) {
    if (_resizeHandle == 4) {
      return r.shift(Offset(delta.dx.clamp(-r.left, 1 - r.right),
          delta.dy.clamp(-r.top, 1 - r.bottom)));
    }
    double l = r.left, t = r.top, ri = r.right, b = r.bottom;
    if (_resizeHandle == 0) {
      l += delta.dx;
      t += delta.dy;
    } else if (_resizeHandle == 1) {
      ri += delta.dx;
      t += delta.dy;
    } else if (_resizeHandle == 2) {
      l += delta.dx;
      b += delta.dy;
    } else if (_resizeHandle == 3) {
      ri += delta.dx;
      b += delta.dy;
    }
    l = l.clamp(0, .98);
    t = t.clamp(0, .98);
    return Rect.fromLTRB(l, t, ri.clamp(l + .02, 1), b.clamp(t + .02, 1));
  }

  @override
  Widget build(BuildContext context) {
    if (!AppBuild.developerTools) {
      return const Scaffold(
          body: Center(child: Text('Developer edition required')));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Template Designer'), actions: [
        IconButton(icon: const Icon(Icons.code), onPressed: _exportTemplate),
        IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => setState(() {
                  if (_designerMode == 0 || _designerMode == 4) {
                    _activeBubbles.clear();
                  } else if (_designerMode == 2 && _answerBoxes.isNotEmpty) {
                    _answerBoxes.removeLast();
                  }
                })),
      ]),
      body: Column(children: [
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.blueAccent.withValues(alpha: 0.1),
            child: const Text("TAP TO ADD • DRAG TO MOVE",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold))),
        Expanded(
            child: Center(
          child: AspectRatio(
            aspectRatio: _imageAspectRatio,
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onTapDown(d, size),
                onPanStart: (d) => _handlePanStart(d, size),
                onPanUpdate: (d) => _handlePanUpdate(d, size),
                onPanEnd: (_) => setState(() {
                  _draggingIndex = null;
                  _activeBoxIndex = null;
                  _resizeHandle = null;
                }),
                child: Stack(children: [
                  Positioned.fill(
                      child: Image.memory(widget.imageBytes, fit: BoxFit.fill)),
                  Positioned.fill(
                      child: CustomPaint(
                          painter: DesignerPainter(bubbles: [
                    ..._bubbles,
                    ..._setBubbles
                  ], answerBoxes: [
                    ..._answerBoxes,
                    if (_qrRect != null) _qrRect!,
                    if (_setRect != null) _setRect!
                  ], mode: _designerMode))),
                ]),
              );
            }),
          ),
        )),
        _buildControls(),
      ]),
      bottomNavigationBar: BottomAppBar(
          color: Colors.grey.shade900,
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Text("ITEMS: ${_bubbles.length}",
                            style: const TextStyle(color: Colors.yellowAccent)),
                        const Spacer(),
                        ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white),
                            onPressed: () {
                              widget.onApply(
                                  _bubbles
                                      .map((b) => b.normalizedPosition)
                                      .toList(),
                                  _answerBoxes,
                                  _qrRect,
                                  _setRect,
                                  _setBubbles
                                      .map((b) => b.normalizedPosition)
                                      .toList());
                              Navigator.pop(context);
                            },
                            child: const Text("SAVE TEMPLATE")),
                      ]))))),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.all(12),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _modeBtn(0, Icons.radio_button_checked, "Bubbles"),
                const SizedBox(width: 8),
                _modeBtn(2, Icons.crop_din, "Boxes"),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              _modeBtn(1, Icons.qr_code, "QR region"),
              const SizedBox(width: 8),
              _modeBtn(3, Icons.crop, "Set region"),
              const SizedBox(width: 8),
              _modeBtn(4, Icons.radio_button_checked, "Set bubbles"),
            ]),
            if (_designerMode == 0 || _designerMode == 4) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.radio_button_checked,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text("Bubble Size:",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _globalRadius,
                      min: 5,
                      max: 40,
                      onChanged: (v) {
                        setState(() {
                          _globalRadius = v;
                          for (int i = 0; i < _bubbles.length; i++) {
                            _bubbles[i] = _bubbles[i].copyWith(radius: v);
                          }
                        });
                      },
                    ),
                  ),
                  Text(_globalRadius.toStringAsFixed(0),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ] else if (_designerMode == 2) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _answerBoxes
                            .add(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.95));
                      });
                    },
                    icon: const Icon(Icons.add_box),
                    label: const Text("ADD COLUMN"),
                  ),
                ],
              ),
            ],
          ],
        ),
      )),
    );
  }

  Widget _modeBtn(int mode, IconData icon, String label) {
    final active = _designerMode == mode;
    return Expanded(
        child: InkWell(
            onTap: () => setState(() {
                  _designerMode = mode;
                  _activeBoxIndex = null;
                  _draggingIndex = null;
                  _resizeHandle = null;
                }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: active ? Colors.blueAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active ? Colors.blueAccent : Colors.grey)),
              child: Column(children: [
                Icon(icon,
                    color: active ? Colors.white : Colors.grey, size: 18),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : Colors.grey,
                        fontSize: 10))
              ]),
            )));
  }

  void _exportTemplate() {
    final String boxes = _answerBoxes
        .map((r) =>
            "      Rect.fromLTRB(${r.left.toStringAsFixed(3)}, ${r.top.toStringAsFixed(3)}, ${r.right.toStringAsFixed(3)}, ${r.bottom.toStringAsFixed(3)}),")
        .join("\n");
    final String code = "answerRegions: [\n$boxes\n    ],\n"
        "qrRegion: $_qrRect,\nsetRegion: $_setRect,\n"
        "answerBubbles: ${_bubbles.map((b) => b.normalizedPosition).toList()},\n"
        "setBubbles: ${_setBubbles.map((b) => b.normalizedPosition).toList()},";
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                backgroundColor: Colors.grey.shade900,
                title: const Text("Export Code",
                    style: TextStyle(color: Colors.white)),
                content: SelectableText(code,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontFamily: 'monospace')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("OK"))
                ]));
  }
}

class DesignerPainter extends CustomPainter {
  final List<BubblePoint> bubbles;
  final List<Rect> answerBoxes;
  final int mode;
  DesignerPainter(
      {required this.bubbles, required this.answerBoxes, required this.mode});
  @override
  void paint(Canvas canvas, Size size) {
    final bPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final boxPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var b in bubbles) {
      canvas.drawCircle(
          Offset(b.normalizedPosition.dx * size.width,
              b.normalizedPosition.dy * size.height),
          b.radius,
          bPaint);
    }

    for (var r in answerBoxes) {
      final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height,
          r.right * size.width, r.bottom * size.height);
      canvas.drawRect(rect, boxPaint);
      if (mode == 1 || mode == 2 || mode == 3) {
        for (var p in [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight
        ]) {
          canvas.drawCircle(p, 6, handlePaint);
          canvas.drawCircle(p, 6, boxPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class BubblePoint {
  final Offset normalizedPosition;
  final double radius;
  BubblePoint({required this.normalizedPosition, required this.radius});
  BubblePoint copyWith({Offset? normalizedPosition, double? radius}) =>
      BubblePoint(
          normalizedPosition: normalizedPosition ?? this.normalizedPosition,
          radius: radius ?? this.radius);
}
