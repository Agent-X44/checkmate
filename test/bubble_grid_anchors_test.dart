import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/models/omr/bubble_grid_anchors.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/models/omr/templates/mixed_30mcq_20tf.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';

void main() {
  final standard = Standard30QuestionsTemplate();
  const column = ColumnAnchors(
      Offset(.2, .3), Offset(.8, .3), Offset(.2, .9), Offset(.8, .9));

  test('interpolates every bubble from four anchors', () {
    final points = BubbleGridAnchors.generate(standard, [column]);
    expect(points.length, 30 * 4);
    expect(points.first, const Offset(.2, .3));
    expect(points[3], const Offset(.8, .3));
    expect(points[4 * 29], const Offset(.2, .9));
    expect(points.last, const Offset(.8, .9));
    // Even spacing across choices and rows.
    expect(points[1].dx, closeTo(.4, 1e-9));
    expect(points[4].dy, closeTo(.3 + .6 / 29, 1e-9));
  });

  test('skewed anchors follow the printed rows', () {
    const skewed = ColumnAnchors(
        Offset(.2, .3), Offset(.8, .32), Offset(.22, .9), Offset(.82, .92));
    final points = BubbleGridAnchors.generate(standard, [skewed]);
    expect(points[3].dy, closeTo(.32, 1e-9));
    expect(points.last, const Offset(.82, .92));
  });

  test('saved bubbles round-trip to the same anchors', () {
    final points = BubbleGridAnchors.generate(standard, [column]);
    final anchors = BubbleGridAnchors.fromBubbles(standard, 1, points)!;
    expect(BubbleGridAnchors.generate(standard, anchors), points);
    expect(BubbleGridAnchors.fromBubbles(standard, 1, points.sublist(1)),
        isNull);
  });

  test('mixed sheets split columns and use A-B for true/false rows', () {
    final mixed = Mixed30Mcq20TfTemplate();
    const right = ColumnAnchors(
        Offset(.7, .3), Offset(.95, .3), Offset(.7, .9), Offset(.95, .9));
    final points = BubbleGridAnchors.generate(mixed, [column, right]);
    expect(points.length, 30 * 4 + 20 * 2);
    // Questions 26-30 are MCQ in column 2; 31-50 are TF with A and B only.
    expect(points[25 * 4], const Offset(.7, .3));
    const firstTf = 30 * 4;
    expect(points[firstTf].dx, closeTo(.7, 1e-9));
    expect(points[firstTf + 1].dx, closeTo(.7 + .25 / 3, 1e-9));
    final anchors = BubbleGridAnchors.fromBubbles(mixed, 2, points)!;
    final again = BubbleGridAnchors.generate(mixed, anchors);
    for (var i = 0; i < points.length; i++) {
      expect((again[i] - points[i]).distance, lessThan(1e-9));
    }
  });

  test('generated templates pass preset validation', () {
    final config = TemplateCalibration.fromTemplate(standard).copyWith(
        answerBubbles: BubbleGridAnchors.generate(standard, [column]));
    expect(
        TemplateCalibration.fromMap(config.toMap()).answerBubbles.length, 120);
  });

  test('starts from the zones the grid reader sampled', () {
    final zones = [
      for (var q = 0; q < 30; q++)
        [
          for (var c = 0; c < 4; c++)
            Rect.fromCenter(
                center: Offset(.2 + c * .2, .3 + q * .02),
                width: .02,
                height: .01)
        ]
    ];
    final anchors = BubbleGridAnchors.fromZones(standard, 1, zones)!.single;
    expect(anchors.firstA, const Offset(.2, .3));
    expect(anchors.lastLast.dx, closeTo(.8, 1e-9));
    expect(anchors.lastLast.dy, closeTo(.3 + 29 * .02, 1e-9));
    expect(BubbleGridAnchors.fromZones(standard, 1, zones.sublist(1)), isNull);
  });
}
