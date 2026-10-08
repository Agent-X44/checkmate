import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:checkmate/config/app_build.dart';
import 'package:checkmate/models/omr/bubble_sheet_template.dart';
import 'package:checkmate/models/omr/template_calibration.dart';
import 'package:checkmate/services/developer_template_store.dart';

const template = BubbleSheetTemplate(
    id: 'test',
    name: 'Test layout',
    answerRegions: [Rect.fromLTRB(.1, .2, .9, .95)],
    totalQuestions: 30,
    choicesPerQuestion: 4,
    gridStart: .25,
    gridWidth: .65);
void main() {
  test('edition matches the requested test build', () {
    expect(
        AppBuild.edition,
        const String.fromEnvironment('TEST_EDITION',
            defaultValue: 'production'));
  });
  test(
      'damaged local preferences do not prevent the developer workspace opening',
      () async {
    SharedPreferences.setMockInitialValues(
        {'checkmate_developer_templates_v1': 'invalid-json'});
    expect(await DeveloperTemplateStore.load(), isEmpty);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('template JSON retains every adjustment and region', () {
    final config = TemplateCalibration.fromTemplate(template).copyWith(
        name: 'Prototype',
        qrRegion: const Rect.fromLTRB(.7, .05, .95, .15),
        setRegion: const Rect.fromLTRB(.1, .05, .3, .1),
        setBubbles: [const Offset(.15, .075)],
        answerBubbles: [const Offset(.4, .3)],
        xOffset: -.03,
        rowSpacing: .5,
        stripHeight: 1.4,
        yOffset: -5,
        fillThreshold: .21,
        zoneWidth: .6,
        zoneHeight: .7,
        bubbleRadius: .007);
    final recovered =
        TemplateCalibration.fromMap(jsonDecode(jsonEncode(config.toMap())));
    expect(recovered.toMap(), config.toMap());
  });
  test('invalid imported profiles cannot reach native sampling', () {
    final valid = TemplateCalibration.fromTemplate(template).toMap();
    for (final change in [
      {'gridStart': .9, 'gridWidth': .65},
      {'fillThreshold': -1},
      {
        'answerRegions': [
          [.9, .2, .1, .9]
        ]
      },
      {'answerRegions': []},
      {
        'answerBubbles': [
          [double.nan, .2]
        ]
      },
      {'yOffset': .5},
      {'version': 2},
    ]) {
      expect(() => TemplateCalibration.fromMap({...valid, ...change}),
          throwsFormatException);
    }
  });
  test('production cannot load or save developer settings', () async {
    if (AppBuild.developerTools) return;
    await expectLater(
        DeveloperTemplateStore.save(TemplateCalibration.fromTemplate(template)),
        throwsStateError);
    expect(await DeveloperTemplateStore.load(), isEmpty);
  });
  test(
      'developer saves, reloads and activates named local profiles without auth',
      () async {
    if (!AppBuild.developerTools) return;
    final base = TemplateCalibration.fromTemplate(template);
    await DeveloperTemplateStore.save(base.copyWith(name: 'First', yOffset: 4));
    await DeveloperTemplateStore.save(
        base.copyWith(name: 'Second', yOffset: 8));
    expect((await DeveloperTemplateStore.active('test'))!.yOffset, 8);
    await DeveloperTemplateStore.save(
        base.copyWith(name: 'First', yOffset: 12));
    expect((await DeveloperTemplateStore.load()).length, 2);
    expect((await DeveloperTemplateStore.active('test'))!.yOffset, 12);
    expect(await DeveloperTemplateStore.active('another-layout'), isNull);
  });
}
