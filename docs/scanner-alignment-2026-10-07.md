# Answer-sheet scanning fixes — 7 October 2026

## Follow-up: missing corner overlay and repeated alignment failures

The scanner no longer draws a QR box or `LOCKED` label. A validated marker
frame draws its outline and a square at each corner circle. Corner updates do
not wait for a QR-first startup window. The tap-to-focus square is cleared even
if the camera rejects a focus or exposure request.

Live QR identification uses ML Kit on supported buffers. The OpenCV worker uses
a single QR locator to guide marker selection, with a bounded decode only for
unsupported ML Kit formats. It no longer runs the still-image QR retry sequence
before returning the live corner overlay. A QR locator error does not prevent
marker detection.

The perspective QR fallback now maps the decoded QR's own points back through
the rectified crop, then restores the crop offset and camera rotation. Previously
it returned the enclosing quadrilateral (potentially the whole header or sheet),
whose center could fail the upper-right QR gate during marker selection. Capture
identity verification and four-marker validation remain required before grading.

Validation: 49 camera-buffer, fiducial geometry, and QR coordinate checks pass.
They were run in an isolated Flutter test harness using the production sources
because the workspace's native hook requires an unavailable Windows C++
toolchain. Static analysis of the changed files is clean, and the Android release
APK builds successfully. Android emulator
startup did not complete, so native image/camera checks still need a device run.

The camera worker now reads padded luminance, Android NV21, and iOS BGRA buffers correctly. Camera and QR positions share the same orientation. Capture uses the rear camera, a detailed still image, automatic focus/exposure, and corrected tap-to-focus coordinates. A verified sheet QR enables capture even when the preview misses registration markers; grading still requires successful alignment in the captured image.

Alignment retries at higher resolution and with a wider local threshold window. It retains small, foreshortened markers, validates their physical size and shape after rectification, corrects perspective bias in ellipse centers, and preserves subpixel centers for the grading transform. Marker selection remains bounded and rejects missing or clipped corner circles. QR fallback rotations now return positions in the original image frame.

The native OpenCV build explicitly includes `objdetect` and its `calib3d` dependencies. Otherwise `QRCodeDetector` remains exposed in Dart but its native symbols are absent. Short sheet identifiers now follow ordinary OMR processing. On pages containing two sheets, capture selects the QR verified for the student; a conflicting captured identity requires a new scan.

Bubble filling uses thresholded ink-pixel density. The previous external-contour area counted the empty interior of a printed circle as ink. Multiple marks still require instructor review. All image processing and grading remain local and deterministic.

## Regression checks

- `test/camera_frame_service_test.dart`: pixel formats, row padding, incomplete buffers, sensor rotation, and oriented dimensions.
- `test/fiducial_geometry_test.dart`: perspective, near-camera ellipse bias, nonuniform contour sampling, clutter, sheet selection by QR, and missing markers.
- `test/sheet_alignment_service_test.dart`: both production artworks with ordinary, strong, extreme, opposite, and close-up perspective, uneven lighting, blur, missing/clipped markers, and interior registration accuracy.
- `test/native_sheet_processing_test.dart`: printed QR coordinates, short Sheet IDs, captured identity checks, and native bubble density.

On a machine with a desktop C++ toolchain, run the corresponding Flutter tests. This workspace currently lacks that Windows toolchain. The reusable Android runner loads the production assets and exercises the native implementation without backend access:

```text
flutter run -d <android-device> -t test/native_alignment_probe.dart
```

The runner prints each result and an `ALIGNMENT_PROBE COMPLETE` summary. A physical-phone check should use both printed layouts, include all four corner circles, and cover close-up focus and steep tilt. A frame missing a marker or with unresolved focus still requires another capture; software cannot recover marks outside the photograph.
