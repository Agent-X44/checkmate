import '../../config/app_build.dart';
import '../../models/omr/bubble_sheet_template.dart';
import '../../models/omr/template_registry.dart';
import 'fiducial_geometry.dart';

class TemplateMarkerMatch {
  final BubbleSheetTemplate template;
  final List<SheetPoint> corners;
  const TemplateMarkerMatch(this.template, this.corners);
}

/// Selects a layout using the printed marker geometry in the captured image.
/// Offline developer scans may try another shipped layout; real assessments
/// always retain the template resolved from their authenticated metadata.
class SheetTemplateSelection {
  static TemplateMarkerMatch? select(
    List<FiducialCandidate> candidates, {
    required BubbleSheetTemplate preferred,
    required double imageArea,
    bool developerSandbox = false,
    SheetPoint? qrCenter,
  }) {
    final templates = [preferred];
    if (AppBuild.developerTools && developerSandbox) {
      final geometries = {
        (preferred.fiducialAspectRatio, preferred.fiducialDiameterRatio)
      };
      for (final template in AnswerSheetTemplateRegistry.all) {
        if (geometries.add(
            (template.fiducialAspectRatio, template.fiducialDiameterRatio))) {
          templates.add(template);
        }
      }
    }
    for (final template in templates) {
      final corners = FiducialGeometry.selectMarkers(candidates,
          imageArea: imageArea,
          aspectRatio: template.fiducialAspectRatio,
          diameterRatio: template.fiducialDiameterRatio,
          qrCenter: qrCenter);
      if (corners != null) return TemplateMarkerMatch(template, corners);
    }
    return null;
  }
}
