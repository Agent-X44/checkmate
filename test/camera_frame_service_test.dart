import 'package:camera/camera.dart';
import 'package:checkmate/services/cv/camera_frame_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Camera stream luminance', () {
    test('NV21 chroma is excluded from the document detector', () {
      final result = CameraFrameService.luminance(
        bytes: Uint8List.fromList([0, 90, 180, 255, 128, 128]),
        width: 2,
        height: 2,
        bytesPerRow: 2,
      );
      expect(result, [0, 90, 180, 255]);
    });

    test('padded luma rows preserve each pixel without padding', () {
      final result = CameraFrameService.luminance(
        bytes: Uint8List.fromList([1, 2, 3, 99, 99, 4, 5, 6]),
        width: 3,
        height: 2,
        bytesPerRow: 5,
      );
      expect(result, [1, 2, 3, 4, 5, 6]);
    });

    test('BGRA markers retain black-white contrast across padded rows', () {
      final result = CameraFrameService.luminance(
        bytes: Uint8List.fromList([
          0, 0, 0, 255, // Black marker.
          255, 255, 255, 255, // White paper.
          99, 99, 99, 99, // Row padding.
          0, 0, 255, 255, // Red.
          255, 0, 0, 255, // Blue.
        ]),
        width: 2,
        height: 2,
        bytesPerRow: 12,
        bytesPerPixel: 4,
      );
      expect(result, [0, 255, 77, 29]);
    });

    test('truncated frames cannot silently add black marker-like pixels', () {
      expect(
        () => CameraFrameService.luminance(
          bytes: Uint8List.fromList([255, 255, 255]),
          width: 2,
          height: 2,
          bytesPerRow: 2,
        ),
        throwsFormatException,
      );
    });
  });

  group('Camera stream orientation', () {
    test('rear sensors with opposite mounting directions both stay upright',
        () {
      for (final sensor in [90, 270]) {
        expect(
          CameraFrameService.rotationDegrees(
            sensorOrientation: sensor,
            orientation: DeviceOrientation.portraitUp,
            lensDirection: CameraLensDirection.back,
            isIOS: false,
          ),
          sensor,
        );
      }
    });

    test('device compensation does not double-rotate landscape sensors', () {
      expect(
        CameraFrameService.rotationDegrees(
          sensorOrientation: 90,
          orientation: DeviceOrientation.landscapeLeft,
          lensDirection: CameraLensDirection.back,
          isIOS: false,
        ),
        0,
      );
      expect(
        CameraFrameService.rotationDegrees(
          sensorOrientation: 90,
          orientation: DeviceOrientation.landscapeRight,
          lensDirection: CameraLensDirection.back,
          isIOS: false,
        ),
        180,
      );
    });

    test('front camera compensation uses its lens direction', () {
      expect(
        CameraFrameService.rotationDegrees(
          sensorOrientation: 270,
          orientation: DeviceOrientation.landscapeLeft,
          lensDirection: CameraLensDirection.front,
          isIOS: false,
        ),
        0,
      );
    });

    test('AVFoundation already delivers an upright portrait buffer', () {
      expect(
        CameraFrameService.rotationDegrees(
          sensorOrientation: 90,
          orientation: DeviceOrientation.portraitUp,
          lensDirection: CameraLensDirection.back,
          isIOS: true,
        ),
        0,
      );
    });

    test('barcode coordinates use the rotated image dimensions', () {
      for (final rotation in [90, 270]) {
        expect(CameraFrameService.uprightSize(1920, 1080, rotation),
            const Size(1080, 1920));
      }
      for (final rotation in [0, 180]) {
        expect(CameraFrameService.uprightSize(1920, 1080, rotation),
            const Size(1920, 1080));
      }
    });
  });
}
