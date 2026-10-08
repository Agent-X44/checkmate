import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Converts the actual camera buffer layout before local document detection.
class CameraFrameService {
  static Uint8List luminance({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    int bytesPerPixel = 1,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        (bytesPerPixel != 1 && bytesPerPixel != 4) ||
        bytesPerRow < width * bytesPerPixel ||
        bytes.length < (height - 1) * bytesPerRow + width * bytesPerPixel) {
      throw const FormatException('Incomplete or unsupported camera frame.');
    }
    // NV21 includes interleaved chroma after the luma plane. Only pass the
    // first width * height bytes to the single-channel OpenCV matrix.
    if (bytesPerPixel == 1 && bytesPerRow == width) {
      return Uint8List.sublistView(bytes, 0, width * height);
    }
    final gray = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * bytesPerRow;
      if (bytesPerPixel == 1) {
        gray.setRange(y * width, (y + 1) * width, bytes, row);
      } else {
        for (var x = 0; x < width; x++) {
          final pixel = row + x * 4;
          // iOS streams BGRA, including row padding. Interpreting B, G, R,
          // and alpha bytes as neighboring gray pixels destroys the markers.
          gray[y * width + x] = (29 * bytes[pixel] +
                  150 * bytes[pixel + 1] +
                  77 * bytes[pixel + 2] +
                  128) >>
              8;
        }
      }
    }
    return gray;
  }

  static int rotationDegrees({
    required int sensorOrientation,
    required DeviceOrientation orientation,
    required CameraLensDirection lensDirection,
    required bool isIOS,
  }) {
    // AVFoundation physically rotates the streaming pixel buffer to the
    // capture orientation. Android exposes the unrotated sensor buffer.
    if (isIOS) return 0;
    final deviceDegrees = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return lensDirection == CameraLensDirection.front
        ? (sensorOrientation + deviceDegrees) % 360
        : (sensorOrientation - deviceDegrees + 360) % 360;
  }

  /// ML Kit returns points in the rotated Android image coordinates.
  static Size uprightSize(int width, int height, int rotationDegrees) {
    return rotationDegrees % 180 == 0
        ? Size(width.toDouble(), height.toDouble())
        : Size(height.toDouble(), width.toDouble());
  }
}
