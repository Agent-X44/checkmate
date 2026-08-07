# Project Maintenance and Optimization Plan

This plan outlines the steps to update dependencies, optimize the project structure, and clean up the codebase for the Checkmate LMS project.

## User Review Required

> [!IMPORTANT]
> - I will be refactoring `main.dart` by extracting `MainNavigation` and `RootAuthWrapper` into separate files in `lib/screens/`.
> - Dependencies will be updated to their latest stable versions. This might cause minor breaking changes in third-party APIs, which I will resolve.

## Proposed Changes

### Dependencies

#### [MODIFY] [pubspec.yaml](file:///C:/AndroidStudioProjects/checkmate/pubspec.yaml)
Update dependencies to latest stable versions based on `flutter pub outdated`.

### Cleanup

#### [DELETE] [test.tar.gz](file:///C:/AndroidStudioProjects/checkmate/test.tar.gz)
Remove this temporary archive file.

### Code Optimization & Refactoring

#### [NEW] [main_navigation.dart](file:///C:/AndroidStudioProjects/checkmate/lib/screens/main_navigation.dart)
Extract the `MainNavigation` widget and its state from `main.dart`.

#### [NEW] [root_auth_wrapper.dart](file:///C:/AndroidStudioProjects/checkmate/lib/screens/root_auth_wrapper.dart)
Extract the `RootAuthWrapper` widget from `main.dart`.

#### [MODIFY] [main.dart](file:///C:/AndroidStudioProjects/checkmate/lib/main.dart)
Clean up `main.dart` to focus on app initialization, theming, and top-level `MaterialApp` configuration.

#### [MODIFY] [image_processor.dart](file:///C:/AndroidStudioProjects/checkmate/lib/services/image_processor.dart)
Review and ensure that OpenCV processing is correctly offloaded to a background isolate as per `AGENTS.md`.

#### [MODIFY] [scanner_screen.dart](file:///C:/AndroidStudioProjects/checkmate/lib/screens/scanner_screen.dart)
Verify that the live camera stream is only used for edge detection and bubble grading is performed on static captures.

### Global Tasks
- Run `dart format .` across the entire project.
- Run `flutter pub upgrade --major-versions`.

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure existing tests pass.
- Run `dart analyze` to check for any linting errors or warnings.

### Manual Verification
- Launch the app and verify:
  - Login flow still works.
  - Navigation between Dashboard, Scanner, and Settings is functional.
  - Theme switching works and persists.
  - Scanner screen initializes the camera correctly.
