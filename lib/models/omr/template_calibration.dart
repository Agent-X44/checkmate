import 'package:flutter/material.dart';
import 'bubble_sheet_template.dart';

/// Local developer preset. Never grants access to LMS data or result writes.
class TemplateCalibration {
  final String name;
  final String baseTemplateId;
  final List<Rect> answerRegions;
  final Rect? qrRegion;
  final Rect? setRegion;
  final List<Offset> setBubbles;
  final List<Offset> answerBubbles;
  final double gridStart, gridWidth, xOffset, rowSpacing, stripHeight;
  final double fillThreshold, zoneWidth, zoneHeight, bubbleRadius;
  final int yOffset;

  const TemplateCalibration(
      {required this.name,
      required this.baseTemplateId,
      required this.answerRegions,
      this.qrRegion,
      this.setRegion,
      this.setBubbles = const [],
      this.answerBubbles = const [],
      this.gridStart = .05,
      this.gridWidth = .92,
      this.xOffset = 0,
      this.rowSpacing = 0,
      this.stripHeight = 1.2,
      this.yOffset = 0,
      this.fillThreshold = .18,
      this.zoneWidth = .45,
      this.zoneHeight = .6,
      this.bubbleRadius = .005});

  factory TemplateCalibration.fromTemplate(BubbleSheetTemplate t) =>
      TemplateCalibration(
          name: t.name,
          baseTemplateId: t.id,
          answerRegions: List.of(t.answerRegions),
          qrRegion: t.qrRegion,
          setRegion: t.setRegion,
          setBubbles: List.of(t.setBubbles ?? []),
          gridStart: t.gridStart,
          gridWidth: t.gridWidth,
          yOffset: t.calibratedYOffset);

  TemplateCalibration copyWith(
          {String? name,
          List<Rect>? answerRegions,
          Rect? qrRegion,
          Rect? setRegion,
          List<Offset>? setBubbles,
          List<Offset>? answerBubbles,
          double? gridStart,
          double? gridWidth,
          double? xOffset,
          double? rowSpacing,
          double? stripHeight,
          int? yOffset,
          double? fillThreshold,
          double? zoneWidth,
          double? zoneHeight,
          double? bubbleRadius}) =>
      TemplateCalibration(
          name: name ?? this.name,
          baseTemplateId: baseTemplateId,
          answerRegions: answerRegions ?? this.answerRegions,
          qrRegion: qrRegion ?? this.qrRegion,
          setRegion: setRegion ?? this.setRegion,
          setBubbles: setBubbles ?? this.setBubbles,
          answerBubbles: answerBubbles ?? this.answerBubbles,
          gridStart: gridStart ?? this.gridStart,
          gridWidth: gridWidth ?? this.gridWidth,
          xOffset: xOffset ?? this.xOffset,
          rowSpacing: rowSpacing ?? this.rowSpacing,
          stripHeight: stripHeight ?? this.stripHeight,
          yOffset: yOffset ?? this.yOffset,
          fillThreshold: fillThreshold ?? this.fillThreshold,
          zoneWidth: zoneWidth ?? this.zoneWidth,
          zoneHeight: zoneHeight ?? this.zoneHeight,
          bubbleRadius: bubbleRadius ?? this.bubbleRadius);

  Map<String, dynamic> toMap() => {
        'version': 1,
        'name': name,
        'baseTemplateId': baseTemplateId,
        'answerRegions': answerRegions
            .map((r) => [r.left, r.top, r.right, r.bottom])
            .toList(),
        'qrRegion': qrRegion == null
            ? null
            : [
                qrRegion!.left,
                qrRegion!.top,
                qrRegion!.right,
                qrRegion!.bottom
              ],
        'setRegion': setRegion == null
            ? null
            : [
                setRegion!.left,
                setRegion!.top,
                setRegion!.right,
                setRegion!.bottom
              ],
        'setBubbles': setBubbles.map((p) => [p.dx, p.dy]).toList(),
        'answerBubbles': answerBubbles.map((p) => [p.dx, p.dy]).toList(),
        'gridStart': gridStart,
        'gridWidth': gridWidth,
        'xOffset': xOffset,
        'rowSpacing': rowSpacing,
        'stripHeight': stripHeight,
        'yOffset': yOffset,
        'fillThreshold': fillThreshold,
        'zoneWidth': zoneWidth,
        'zoneHeight': zoneHeight,
        'bubbleRadius': bubbleRadius,
      };

  factory TemplateCalibration.fromMap(Map<String, dynamic> m) {
    double number(String key, double min, double max) {
      final value = m[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid $key');
      }
      return value.toDouble();
    }

    Rect? rect(dynamic value) {
      if (value == null) return null;
      if (value is! List ||
          value.length != 4 ||
          value.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
        throw const FormatException('Invalid region');
      }
      final r = Rect.fromLTRB(
          (value[0] as num).toDouble(),
          (value[1] as num).toDouble(),
          (value[2] as num).toDouble(),
          (value[3] as num).toDouble());
      if (r.width <= 0 || r.height <= 0) {
        throw const FormatException('Empty region');
      }
      return r;
    }

    List<Offset> points(dynamic value) {
      if (value is! List || value.length > 200) {
        throw const FormatException('Invalid bubbles');
      }
      return value.map<Offset>((v) {
        if (v is! List ||
            v.length != 2 ||
            v.any((x) => x is! num || !x.isFinite || x < 0 || x > 1)) {
          throw const FormatException('Invalid bubble position');
        }
        return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      }).toList();
    }

    final regions = m['answerRegions'];
    if (m['version'] != 1 ||
        m['name'] is! String ||
        m['name'].toString().trim().isEmpty ||
        m['baseTemplateId'] is! String ||
        regions is! List ||
        regions.isEmpty ||
        regions.length > 4) {
      throw const FormatException('Invalid template preset');
    }
    final y = number('yOffset', -200, 200);
    if (y != y.roundToDouble()) throw const FormatException('Invalid yOffset');
    // The printed A-D row can be slightly wider than its column box, so the
    // grid may overhang the region; it must still overlap it substantially.
    final gridEnd = number('gridStart', -.5, 1) + number('gridWidth', .01, 2);
    if (gridEnd > 1.5 || gridEnd <= 0) {
      throw const FormatException(
          'The bubble grid must stay over the answer region');
    }
    return TemplateCalibration(
        name: m['name'],
        baseTemplateId: m['baseTemplateId'],
        answerRegions: regions.map((r) => rect(r)!).toList(),
        qrRegion: rect(m['qrRegion']),
        setRegion: rect(m['setRegion']),
        setBubbles: points(m['setBubbles']),
        answerBubbles: points(m['answerBubbles']),
        gridStart: number('gridStart', -.5, 1),
        gridWidth: number('gridWidth', .01, 2),
        xOffset: number('xOffset', -.5, .5),
        rowSpacing: number('rowSpacing', -10, 10),
        stripHeight: number('stripHeight', .3, 3),
        yOffset: y.toInt(),
        fillThreshold: number('fillThreshold', .01, .9),
        zoneWidth: number('zoneWidth', .1, 1),
        zoneHeight: number('zoneHeight', .1, 1),
        bubbleRadius: number('bubbleRadius', .001, .03));
  }
}
