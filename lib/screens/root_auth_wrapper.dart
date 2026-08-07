import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

/// Helper class to handle navigation context correctly
class RootAuthWrapper extends StatelessWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;

  const RootAuthWrapper(
      {super.key, required this.themeMode, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    return LoginScreen(onLogin: () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MainNavigation(
            themeMode: themeMode,
            onThemeChanged: onThemeChanged,
          ),
        ),
      );
    });
  }
}
