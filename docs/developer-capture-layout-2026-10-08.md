# Offline developer capture layout selection

The developer camera could show a detected paper frame and then report an alignment failure. Live preview tried both shipped registration-marker geometries, while still capture used only the selected template. The developer workspace initially selected the 50-question template, so an ordinary 30-question sheet could fail during capture.

Offline developer capture now tests the selected template against the four markers in the actual photograph and, if necessary, tries the other shipped physical layout. It never uses stale preview coordinates to align a still photo. The matching layout controls the warp dimensions, answer regions and question capacity. A selected mixed MCQ/TF layout is retained when its physical markers match; marker geometry cannot infer question types.

Processed sheets retain their base template ID even when a local preset has a custom name. Both camera and imported-photo flows open developer tools for that detected template. Only presets belonging to the detected template are applied, including when the selected layout changed during capture.

Layout fallback requires both the developer build and offline sandbox mode. Signed-in assessment scanning and production builds retain their resolved template and captured QR identity checks. Missing or invalid marker frames still fail alignment. Raw images and offline test grades stay on the device.

Android packaging now refreshes the app's JNI merge step in both editions. Binary inspection found a fresh Dart compilation followed by an unchanged APK containing the previous developer UI. This matches the [Flutter 3.44 flavored-build regression](https://github.com/flutter/flutter/issues/187553). Refreshing that small merge step prevents an ordinary incremental build from silently shipping earlier scanner code.

Both universal APKs were rebuilt successfully. The compiled and merged app libraries have matching hashes, and the APK's stripped app library retains the same ELF build ID as the fresh compilation for all three architectures. The developer APK contains the new layout-selection UI. Both APK signatures verify, and `build/releases/SHA256SUMS.txt` matches the copied release files.

The isolated Flutter suite passes 26 tests in each edition, including layout mismatch, missing corners, production exclusion, mixed-layout preservation, automatic evaluation saving and template persistence. Static analysis passes. Android native cases for wrong selected layouts, matching preset application and missing markers were added to `test/native_alignment_probe.dart` and `test/native_sheet_processing_test.dart`. The attempted emulator did not remain available through ADB, so those native cases and real camera checks still need an Android device:

```powershell
C:/flutter/bin/flutter.bat run --flavor developer -d <device-id> -t test/native_alignment_probe.dart
```
