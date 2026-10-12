import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/theme/checkmate_theme.dart';

void main() {
  testWidgets('CheckMate smoke test', (WidgetTester tester) async {
    // CheckMateApp first shows a spinner while Supabase and platform plugins
    // start, so check the signed-out screen it then shows.
    await tester.pumpWidget(
        MaterialApp(theme: CheckMateTheme.light, home: const LoginScreen()));
    await tester.pump();

    expect(find.text('CheckMate LMS'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
