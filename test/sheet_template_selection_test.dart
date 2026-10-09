import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/config/app_build.dart';
import 'package:checkmate/models/omr/templates/standard_30_questions.dart';
import 'package:checkmate/models/omr/templates/standard_50_questions.dart';
import 'package:checkmate/models/omr/templates/mixed_15mcq_15tf.dart';
import 'package:checkmate/services/cv/fiducial_geometry.dart';
import 'package:checkmate/services/cv/sheet_template_selection.dart';
import 'fiducial_geometry_test.dart' show circle, frame, cameraImageArea;
import 'sheet_evaluation_service_test.dart' show evaluationFixture;

List<FiducialCandidate> narrowMarkers() => frame
    .map((p) =>
        circle(p, .090, .320, [330, 12, 150, 15, 330 / .320, 70, .04, .05]))
    .toList();
List<FiducialCandidate> wideMarkers() => frame
    .map((p) =>
        circle(p, .063, .681, [650, 18, 150, 15, 650 / .681, 70, .04, .05]))
    .toList();

void main() {
  test('matching selected mixed layout retains its question configuration', () {
    final markers = narrowMarkers();
    final preferred = Mixed15Mcq15TfTemplate();
    final match = SheetTemplateSelection.select(markers,
        preferred: preferred,
        imageArea: cameraImageArea(markers),
        developerSandbox: true);
    expect(match?.template.id, preferred.id);
    expect(match?.template.tfCount, 15);
  });
  test(
      'developer capture recognizes narrow paper despite the default 50 layout',
      () {
    final markers = narrowMarkers();
    final match = SheetTemplateSelection.select(markers,
        preferred: Standard50QuestionsTemplate(),
        imageArea: cameraImageArea(markers),
        developerSandbox: true);
    expect(match?.template.id,
        AppBuild.developerTools ? Standard30QuestionsTemplate().id : null);
    if (AppBuild.developerTools) expect(match!.corners, hasLength(4));
  });
  test('developer capture recognizes wide paper when 30 was selected', () {
    final markers = wideMarkers();
    final match = SheetTemplateSelection.select(markers,
        preferred: Standard30QuestionsTemplate(),
        imageArea: cameraImageArea(markers),
        developerSandbox: true);
    expect(match?.template.id,
        AppBuild.developerTools ? Standard50QuestionsTemplate().id : null);
  });
  test('real assessments reject a different printed layout in both editions',
      () {
    final markers = narrowMarkers();
    expect(
        SheetTemplateSelection.select(markers,
            preferred: Standard50QuestionsTemplate(),
            imageArea: cameraImageArea(markers)),
        isNull);
  });
  test('auto selection cannot replace a missing corner with an invented point',
      () {
    final markers = narrowMarkers()..removeLast();
    expect(
        SheetTemplateSelection.select(markers,
            preferred: Standard50QuestionsTemplate(),
            imageArea: cameraImageArea(markers),
            developerSandbox: true),
        isNull);
  });
  test('base layout survives evaluation copies and named developer presets',
      () {
    final sheet = evaluationFixture([]).copyWith(
        templateId: Standard30QuestionsTemplate().id,
        templateName: 'Renamed local calibration');
    final copied = sheet.copyWith(questionDetails: []);
    expect(copied.templateId, Standard30QuestionsTemplate().id);
    expect(copied.toMap()['templateId'], Standard30QuestionsTemplate().id);
  });
}
