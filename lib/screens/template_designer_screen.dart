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
  double _globalRadius = 15.0; 
  int? _draggingIndex;
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
                  ],
                );
              },
            ),
          ),
          _buildSizeControl(),
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

  Widget _buildSizeControl() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
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
                  // Apply to all existing bubbles for convenience
                  for (int i = 0; i < _bubbles.length; i++) {
                    _bubbles[i] = _bubbles[i].copyWith(radius: v);
                  }
                });
              },
            ),
          ),
          Text(_globalRadius.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
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
      ),
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
