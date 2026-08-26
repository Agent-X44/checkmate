import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/main.dart';

void main() {
  testWidgets('CheckMate smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CheckMateApp());

    // Verify that the login screen is shown (CheckMate text should be present)
    expect(find.text('CheckMate'), findsAtLeastNWidgets(1));
  });
}
