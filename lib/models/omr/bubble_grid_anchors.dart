import 'package:flutter/material.dart';
import 'bubble_sheet_template.dart';

/// Four bubble centres that define one answer column, normalized to the
/// warped sheet: the first and last choice of its first and last rows.
/// Every other bubble is interpolated between them, which also absorbs
/// slight rotation or keystone left after warping.
class ColumnAnchors {
  final Offset firstA, firstLast, lastA, lastLast;
  const ColumnAnchors(this.firstA, this.firstLast, this.lastA, this.lastLast);

  List<Offset> get points => [firstA, firstLast, lastA, lastLast];

  ColumnAnchors withPoint(int index, Offset value) {
    final p = List.of(points)..[index] = value;
    return ColumnAnchors(p[0], p[1], p[2], p[3]);
  }

  /// Moves the whole column, keeping its shape.
  ColumnAnchors shifted(Offset delta) => ColumnAnchors(
      firstA + delta, firstLast + delta, lastA + delta, lastLast + delta);
}

/// Builds the ordered manual-bubble list the OMR engine samples
/// (question order, then choice; A-B for TF rows) from per-column anchors.
abstract final class BubbleGridAnchors {
  /// Questions per answer region, split exactly as the grid reader does.
  static List<int> questionsPerColumn(BubbleSheetTemplate t, int regions) {
    final per = (t.totalQuestions / regions).ceil();
    return [
      for (var i = 0; i < regions; i++)
        i == regions - 1 ? t.totalQuestions - per * i : per
    ];
  }

  static int choicesFor(BubbleSheetTemplate t, int question) =>
      t.tfCount > 0 && question >= t.mcqCount ? 2 : t.choicesPerQuestion;

  /// Centre of [choice] in row [row] of a column with [rows] rows.
  static Offset centre(
      ColumnAnchors a, int rows, int row, int choices, int choice) {
    final t = rows <= 1 ? 0.0 : row / (rows - 1);
    final s = choices <= 1 ? 0.0 : choice / (choices - 1);
    final left = Offset.lerp(a.firstA, a.lastA, t)!;
    final right = Offset.lerp(a.firstLast, a.lastLast, t)!;
    return Offset.lerp(left, right, s)!;
  }

  static List<Offset> generate(
      BubbleSheetTemplate t, List<ColumnAnchors> columns) {
    final rows = questionsPerColumn(t, columns.length);
    final full = t.choicesPerQuestion;
    final points = <Offset>[];
    var question = 0;
    for (var c = 0; c < columns.length; c++) {
      for (var r = 0; r < rows[c]; r++, question++) {
        // TF rows use the first two printed positions (A and B).
        for (var k = 0; k < choicesFor(t, question); k++) {
          final p = centre(columns[c], rows[c], r, full, k);
          points.add(Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)));
        }
      }
    }
    return points;
  }

  /// Recovers anchors from a saved bubble list, or null if it does not match
  /// this template's question and choice counts.
  static List<ColumnAnchors>? fromBubbles(
      BubbleSheetTemplate t, int regions, List<Offset> bubbles) {
    final expected = [
      for (var q = 0; q < t.totalQuestions; q++) choicesFor(t, q)
    ];
    if (bubbles.length != expected.fold<int>(0, (a, b) => a + b)) return null;
    final starts = <int>[];
    var offset = 0;
    for (final n in expected) {
      starts.add(offset);
      offset += n;
    }
    Offset last(int q) {
      final a = bubbles[starts[q]];
      final b = bubbles[starts[q] + expected[q] - 1];
      final scale = (t.choicesPerQuestion - 1) / (expected[q] - 1);
      return a + (b - a) * scale;
    }

    final rows = questionsPerColumn(t, regions);
    final columns = <ColumnAnchors>[];
    var first = 0;
    for (final n in rows) {
      final end = first + n - 1;
      columns.add(ColumnAnchors(bubbles[starts[first]], last(first),
          bubbles[starts[end]], last(end)));
      first += n;
    }
    return columns;
  }

  /// Anchors from the zones the grid reader actually sampled, so the builder
  /// starts where the current grading already is.
  static List<ColumnAnchors>? fromZones(
      BubbleSheetTemplate t, int regions, List<List<Rect>> zones) {
    if (zones.length != t.totalQuestions ||
        zones.any((z) => z.length != t.choicesPerQuestion)) {
      return null;
    }
    final rows = questionsPerColumn(t, regions);
    final columns = <ColumnAnchors>[];
    var first = 0;
    for (final n in rows) {
      final end = first + n - 1;
      columns.add(ColumnAnchors(
          zones[first].first.center,
          zones[first].last.center,
          zones[end].first.center,
          zones[end].last.center));
      first += n;
    }
    return columns;
  }

  /// A neutral starting guess inside each answer region.
  static List<ColumnAnchors> fromRegions(
      BubbleSheetTemplate t, List<Rect> regions) {
    final rows = questionsPerColumn(t, regions.length);
    return [
      for (var i = 0; i < regions.length; i++)
        () {
          final r = regions[i];
          final half = r.height / rows[i] / 2;
          final top = r.top + half, bottom = r.bottom - half;
          final left = r.left + r.width * .2, right = r.left + r.width * .85;
          return ColumnAnchors(Offset(left, top), Offset(right, top),
              Offset(left, bottom), Offset(right, bottom));
        }()
    ];
  }
}
