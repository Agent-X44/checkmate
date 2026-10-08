import 'package:checkmate/services/cv/live_scan_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'old or future-frame coordinates must not be drawn on the current preview',
      () {
    expect(LiveScanPolicy.isFresh(1000000, 1020000), isTrue);
    expect(LiveScanPolicy.isFresh(1000000, 1249999), isTrue);
    expect(LiveScanPolicy.isFresh(1000000, 1250000), isFalse);
    expect(LiveScanPolicy.isFresh(1000000, 2000000), isFalse);
    expect(LiveScanPolicy.isFresh(1000000, 999999), isFalse);
  });
}
