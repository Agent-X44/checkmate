/// Live preview limits are separate from full-resolution still-photo grading.
class LiveScanPolicy {
  static const frameInterval = Duration(milliseconds: 33);
  static const maxOverlayAge = Duration(milliseconds: 250);
  static const previewMaxDimension = 960;
  static const qrInterval = Duration(milliseconds: 250);

  static bool isFresh(int capturedAtMicros, int nowMicros) =>
      capturedAtMicros <= nowMicros &&
      nowMicros - capturedAtMicros < maxOverlayAge.inMicroseconds;
}
