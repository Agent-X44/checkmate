/// Live preview limits are separate from full-resolution still-photo grading.
class LiveScanPolicy {
  static const frameInterval = Duration(milliseconds: 33);
  // A phone takes 100-200 ms to process a preview frame. Each result stays
  // drawn until the next replaces it, so its age limit must exceed that
  // latency or the frame only flickers; half a second still follows a
  // hand-held sheet closely.
  static const maxOverlayAge = Duration(milliseconds: 500);
  static const previewMaxDimension = 960;
  static const qrInterval = Duration(milliseconds: 250);

  static bool isFresh(int capturedAtMicros, int nowMicros) =>
      capturedAtMicros <= nowMicros &&
      nowMicros - capturedAtMicros < maxOverlayAge.inMicroseconds;
}
