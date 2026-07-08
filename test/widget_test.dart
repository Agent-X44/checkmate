import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/main.dart';

void main() {
  testWidgets('Checkmate smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CheckmateApp());

    // Verify that the login screen is shown (Checkmate text should be present)
    expect(find.text('Checkmate'), findsAtLeastNWidgets(1));
  });
}
