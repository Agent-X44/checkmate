import 'dart:typed_data';
import 'package:flutter/material.dart';

class TemplateDesignerScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Offset>? initialBubbles;
  final Function(List<Offset>) onApply;

  const TemplateDesignerScreen({
    super.key, 
    required this.imageBytes, 
    this.initialBubbles,
    required this.onApply,
  });

  @override
  State<TemplateDesignerScreen> createState() => _TemplateDesignerScreenState();
}

class _TemplateDesignerScreenState extends State<TemplateDesignerScreen> {
  late List<BubblePoint> _bubbles;
  Rect? _qrRect; // Normalized QR region
  bool _isQrMode = false;
  double _globalRadius = 15.0; 
  int? _draggingIndex;
  bool _isDraggingQr = false;
  int? _qrResizeHandle; // 0: TL, 1: TR, 2: BL, 3: BR
  final int _choicesCount = 5;

  @override
  void initState() {
    super.initState();
    _bubbles = widget.initialBubbles?.map((p) => BubblePoint(
      normalizedPosition: p, 
      radius: _globalRadius,
    )).toList() ?? [];
  }

  void _addBubble(Offset localPosition, Size areaSize) {
    if (_isQrMode) {
      setState(() {
        _qrRect = Rect.fromLTWH(
          localPosition.dx / areaSize.width,
          localPosition.dy / areaSize.height,
          0.1,
          0.1,
        );
      });
      return;
    }
    setState(() {
      _bubbles.add(BubblePoint(
        normalizedPosition: Offset(
          localPosition.dx / areaSize.width,
          localPosition.dy / areaSize.height,
        ),
        radius: _globalRadius,
      ));
    });
  }

  void _handlePanStart(DragStartDetails details, Size areaSize) {
    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(details.globalPosition);

    // Check QR handles first if in QR mode
    if (_isQrMode && _qrRect != null) {
      final rect = Rect.fromLTRB(
        _qrRect!.left * areaSize.width,
        _qrRect!.top * areaSize.height,
        _qrRect!.right * areaSize.width,
        _qrRect!.bottom * areaSize.height,
      );

      final handles = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];

      for (int i = 0; i < handles.length; i++) {
        if ((handles[i] - localPosition).distance < 20) {
          setState(() {
            _qrResizeHandle = i;
          });
          return;
        }
      }

      if (rect.contains(localPosition)) {
        setState(() {
          _isDraggingQr = true;
        });
        return;
      }
    }

    for (int i = 0; i < _bubbles.length; i++) {
      final pos = Offset(
        _bubbles[i].normalizedPosition.dx * areaSize.width,
        _bubbles[i].normalizedPosition.dy * areaSize.height,
      );
      if ((pos - localPosition).distance < _bubbles[i].radius * 2) {
        setState(() {
          _draggingIndex = i;
        });
        break;
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Size areaSize) {
    if (_qrResizeHandle != null && _qrRect != null) {
      setState(() {
        double l = _qrRect!.left, t = _qrRect!.top, r = _qrRect!.right, b = _qrRect!.bottom;
        final dx = details.delta.dx / areaSize.width;
        final dy = details.delta.dy / areaSize.height;

        if (_qrResizeHandle == 0) { l += dx; t += dy; }
        else if (_qrResizeHandle == 1) { r += dx; t += dy; }
        else if (_qrResizeHandle == 2) { l += dx; b += dy; }
        else if (_qrResizeHandle == 3) { r += dx; b += dy; }

        _qrRect = Rect.fromLTRB(l.clamp(0, r - 0.01), t.clamp(0, b - 0.01), r.clamp(l + 0.01, 1), b.clamp(t + 0.01, 1));
      });
      return;
    }

    if (_isDraggingQr && _qrRect != null) {
      setState(() {
        _qrRect = _qrRect!.shift(Offset(
          details.delta.dx / areaSize.width,
          details.delta.dy / areaSize.height,
        ));
      });
      return;
    }

    if (_draggingIndex != null) {
      setState(() {
        final currentPos = Offset(
          _bubbles[_draggingIndex!].normalizedPosition.dx * areaSize.width,
          _bubbles[_draggingIndex!].normalizedPosition.dy * areaSize.height,
        );
        final newPos = currentPos + details.delta;
        _bubbles[_draggingIndex!] = _bubbles[_draggingIndex!].copyWith(
          normalizedPosition: Offset(
            newPos.dx / areaSize.width,
            newPos.dy / areaSize.height,
          ),
        );
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _draggingIndex = null;
      _isDraggingQr = false;
      _qrResizeHandle = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Template Designer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            onPressed: _exportTemplate,
            tooltip: "Export Template",
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => setState(() => _bubbles.clear()),
            tooltip: "Clear",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                    GestureDetector(
                      onTapDown: (details) => _addBubble(details.localPosition, size),
                      onPanStart: (details) => _handlePanStart(details, size),
                      onPanUpdate: (details) => _handlePanUpdate(details, size),
                      onPanEnd: _handlePanEnd,
                      child: Container(
                        color: Colors.transparent,
                        width: size.width,
                        height: size.height,
                      ),
                    ),
                    ..._bubbles.asMap().entries.map((entry) {
                      final pos = Offset(
                        entry.value.normalizedPosition.dx * size.width,
                        entry.value.normalizedPosition.dy * size.height,
                      );
                      return Positioned(
                        left: pos.dx - entry.value.radius,
                        top: pos.dy - entry.value.radius,
                        child: IgnorePointer(
                          child: Container(
                            width: entry.value.radius * 2,
                            height: entry.value.radius * 2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.yellowAccent, width: 2),
                              color: Colors.yellowAccent.withValues(alpha: 0.3),
                            ),
                            child: Center(
                              child: Text(
                                (entry.key + 1).toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 8),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (_qrRect != null)
                      Positioned(
                        left: _qrRect!.left * size.width,
                        top: _qrRect!.top * size.height,
                        child: IgnorePointer(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: _qrRect!.width * size.width,
                                height: _qrRect!.height * size.height,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.blueAccent, width: 3),
                                  color: Colors.blueAccent.withValues(alpha: 0.2),
                                ),
                                child: const Center(
                                  child: Icon(Icons.qr_code, color: Colors.white, size: 30),
                                ),
                              ),
                              if (_isQrMode) ...[
                                _qrHandle(0, 0),
                                _qrHandle(_qrRect!.width * size.width, 0),
                                _qrHandle(0, _qrRect!.height * size.height),
                                _qrHandle(_qrRect!.width * size.width, _qrRect!.height * size.height),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildControls(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.grey.shade900,
        height: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text("Bubbles: ${_bubbles.length}", style: const TextStyle(color: Colors.yellowAccent)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  widget.onApply(_bubbles.map((b) => b.normalizedPosition).toList());
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_circle),
                label: const Text("USE TEMPLATE"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qrHandle(double left, double top) {
    return Positioned(
      left: left - 8,
      top: top - 8,
      child: Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _modeButton(Icons.radio_button_checked, "Bubbles", !_isQrMode),
              const SizedBox(width: 10),
              _modeButton(Icons.qr_code, "QR Code", _isQrMode),
            ],
          ),
          const Divider(color: Colors.grey, height: 16),
          if (!_isQrMode) 
            Row(
              children: [
                const Icon(Icons.radio_button_checked, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text("Bubble Size:", style: TextStyle(color: Colors.white, fontSize: 12)),
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
                Text(_globalRadius.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 10)),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Tap to place QR box, drag to move, corners to resize",
                style: TextStyle(color: Colors.blueAccent, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeButton(IconData icon, String label, bool isActive) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _isQrMode = label == "QR Code"),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? Colors.blueAccent : Colors.grey),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  void _exportTemplate() {
    if (_bubbles.isEmpty) return;

    double minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (var b in _bubbles) {
      if (b.normalizedPosition.dx < minX) minX = b.normalizedPosition.dx;
      if (b.normalizedPosition.dx > maxX) maxX = b.normalizedPosition.dx;
      if (b.normalizedPosition.dy < minY) minY = b.normalizedPosition.dy;
      if (b.normalizedPosition.dy > maxY) maxY = b.normalizedPosition.dy;
    }

    final double l = (minX - 0.02).clamp(0.0, 1.0);
    final double t = (minY - 0.02).clamp(0.0, 1.0);
    final double r = (maxX + 0.02).clamp(0.0, 1.0);
    final double b = (maxY + 0.02).clamp(0.0, 1.0);

    final String qrCode = _qrRect == null ? "" : """
      qrRegion: Rect.fromLTRB(
        ${_qrRect!.left.toStringAsFixed(3)}, 
        ${_qrRect!.top.toStringAsFixed(3)}, 
        ${_qrRect!.right.toStringAsFixed(3)}, 
        ${_qrRect!.bottom.toStringAsFixed(3)}
      ),""";

    final String code = """
  /// Copy this into lib/models/omr/templates/your_template.dart
  factory BubbleSheetTemplate.customExam() {
    return const BubbleSheetTemplate(
      name: 'Custom Exam Sheet',
      paperAspectRatio: 0.0, 
      answerRegion: Rect.fromLTRB(
        ${l.toStringAsFixed(3)}, 
        ${t.toStringAsFixed(3)}, 
        ${r.toStringAsFixed(3)}, 
        ${b.toStringAsFixed(3)}
      ),$qrCode
      totalQuestions: 5, 
      choicesPerQuestion: $_choicesCount,
    );
  }

  // Point Map
  // static const List<double> customXOffsets = [
  //   ${_bubbles.take(_choicesCount).map((bp) => bp.normalizedPosition.dx.toStringAsFixed(3)).join(", ")}
  // ];
""";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Row(
          children: [
            Icon(Icons.code, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text("Production Template Code", style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            code, 
            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("DONE")
          ),
        ],
      ),
    );
  }
}

class BubblePoint {
  final Offset normalizedPosition;
  final double radius;
  BubblePoint({required this.normalizedPosition, required this.radius});

  BubblePoint copyWith({Offset? normalizedPosition, double? radius}) {
    return BubblePoint(
      normalizedPosition: normalizedPosition ?? this.normalizedPosition,
      radius: radius ?? this.radius,
    );
  }
}
