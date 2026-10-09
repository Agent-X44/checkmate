import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/omr/processed_sheet.dart';

/// How one sampled choice is drawn over the sheet.
enum BubbleMark { correct, wrong, detected, missedKey, empty }

/// Overlay colors are drawn on paper, so they stay fixed in both themes.
abstract final class SheetOverlayColors {
  static const correct = Color(0xFF2ECC71);
  static const wrong = Color(0xFFE53935);
  static const detected = Color(0xFF29B6F6);
  static const empty = Color(0xFFFFEB3B);
  static const region = Color(0xFF00E5FF);
  static const guide = Color(0xFFFFC107);

  static Color of(BubbleMark mark) => switch (mark) {
        BubbleMark.correct || BubbleMark.missedKey => correct,
        BubbleMark.wrong => wrong,
        BubbleMark.detected => detected,
        BubbleMark.empty => empty,
      };
}

/// Classifies choice [choice] of question [index] from the local detection
/// and, when graded, the evaluated answer key.
BubbleMark bubbleMark(ProcessedSheet sheet, int index, int choice) {
  final result = sheet.results[index];
  final letter = String.fromCharCode(65 + choice);
  final marked =
      result.multipleAnswers.contains(letter) || result.answer == letter;
  final key = index < sheet.questionDetails.length
      ? sheet.questionDetails[index]['correct_answer']?.toString()
      : null;
  if (marked) {
    if (result.isAmbiguous) return BubbleMark.wrong;
    if (key == null) return BubbleMark.detected;
    return letter == key ? BubbleMark.correct : BubbleMark.wrong;
  }
  return key == letter ? BubbleMark.missedKey : BubbleMark.empty;
}

/// The warped sheet with every sampled bubble outlined by its grading state.
/// Pinch to zoom and drag to pan.
class SheetOverlayView extends StatefulWidget {
  final ProcessedSheet sheet;

  /// Shows only the answer area (with its printed header) instead of the
  /// whole sheet.
  final bool cropToAnswers;

  /// Configured regions not yet applied, drawn as a thin guide.
  final List<Rect> guideRegions;

  const SheetOverlayView(
      {super.key,
      required this.sheet,
      this.cropToAnswers = true,
      this.guideRegions = const []});

  @override
  State<SheetOverlayView> createState() => _SheetOverlayViewState();
}

class _SheetOverlayViewState extends State<SheetOverlayView> {
  ui.Image? _image;
  bool _failed = false;
  Uint8List? _decoding;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(SheetOverlayView old) {
    super.didUpdateWidget(old);
    if (!identical(old.sheet.warpedImage, widget.sheet.warpedImage)) _decode();
  }

  Future<void> _decode() async {
    final bytes = widget.sheet.warpedImage;
    _decoding = bytes;
    if (bytes.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      final image = await decodeImageFromList(bytes);
      if (!mounted || !identical(_decoding, bytes)) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _failed = false;
      });
    } catch (_) {
      if (mounted && identical(_decoding, bytes)) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect _crop() {
    final regions = [...widget.sheet.sampledRegions, ...widget.guideRegions];
    if (!widget.cropToAnswers || regions.isEmpty) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final union = regions.reduce((a, b) => a.expandToInclude(b));
    // Full width keeps question numbers and the A-D header row in view.
    return Rect.fromLTRB(
        0, math.max(0, union.top - .04), 1, math.min(1, union.bottom + .015));
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (_failed) {
      return const Center(child: Text('Image preview unavailable.'));
    }
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final crop = _crop();
    final aspect = crop.width * image.width / (crop.height * image.height);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = width / aspect;
      return InteractiveViewer(
        constrained: false,
        minScale: 1,
        maxScale: 8,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _SheetOverlayPainter(
                image: image,
                sheet: widget.sheet,
                crop: crop,
                guideRegions: widget.guideRegions),
          ),
        ),
      );
    });
  }
}

class _SheetOverlayPainter extends CustomPainter {
  final ui.Image image;
  final ProcessedSheet sheet;
  final Rect crop;
  final List<Rect> guideRegions;

  _SheetOverlayPainter(
      {required this.image,
      required this.sheet,
      required this.crop,
      required this.guideRegions});

  Rect _map(Rect r, Size size) => Rect.fromLTRB(
      (r.left - crop.left) / crop.width * size.width,
      (r.top - crop.top) / crop.height * size.height,
      (r.right - crop.left) / crop.width * size.width,
      (r.bottom - crop.top) / crop.height * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
        crop.left * image.width,
        crop.top * image.height,
        crop.width * image.width,
        crop.height * image.height);
    canvas.drawImageRect(image, source, Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);

    final stroke = math.max(1.5, size.width / 450);
    for (final region in sheet.sampledRegions) {
      final r = _map(region, size);
      canvas.drawRect(
          r, Paint()..color = SheetOverlayColors.region.withValues(alpha: .08));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = SheetOverlayColors.region);
    }
    for (final region in guideRegions) {
      canvas.drawRect(
          _map(region, size),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * .7
            ..color = SheetOverlayColors.guide.withValues(alpha: .9));
    }

    final count = math.min(sheet.results.length, sheet.bubbleZones.length);
    for (var q = 0; q < count; q++) {
      final zones = sheet.bubbleZones[q];
      for (var c = 0; c < zones.length; c++) {
        final mark = bubbleMark(sheet, q, c);
        final color = SheetOverlayColors.of(mark);
        final oval = _map(zones[c], size);
        final filled = mark != BubbleMark.empty && mark != BubbleMark.missedKey;
        canvas.drawOval(
            oval, Paint()..color = color.withValues(alpha: filled ? .38 : .14));
        canvas.drawOval(
            oval,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = mark == BubbleMark.empty ? stroke : stroke * 1.6
              ..color = color.withValues(alpha: filled ? 1 : .85));
      }
    }
  }

  @override
  bool shouldRepaint(_SheetOverlayPainter old) =>
      old.image != image ||
      old.sheet != sheet ||
      old.crop != crop ||
      old.guideRegions != guideRegions;
}

/// Key for the overlay colors. Graded sheets show correct/wrong/missed;
/// ungraded previews show detected marks.
class SheetOverlayLegend extends StatelessWidget {
  final bool graded;
  const SheetOverlayLegend({super.key, required this.graded});

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label, {bool hollow = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 11,
              decoration: BoxDecoration(
                color: hollow ? null : color.withValues(alpha: .45),
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
    return Wrap(spacing: 16, runSpacing: 6, children: [
      if (graded) ...[
        item(SheetOverlayColors.correct, 'Correct'),
        item(SheetOverlayColors.wrong, 'Wrong / ambiguous'),
        item(SheetOverlayColors.correct, 'Missed key', hollow: true),
      ] else
        item(SheetOverlayColors.detected, 'Detected mark'),
      item(SheetOverlayColors.empty, 'Unmarked', hollow: true),
      item(SheetOverlayColors.region, 'Answer region', hollow: true),
    ]);
  }
}
