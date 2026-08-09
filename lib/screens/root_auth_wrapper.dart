import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

class RootAuthWrapper extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;

  const RootAuthWrapper(
      {super.key, required this.themeMode, required this.onThemeChanged});

  @override
  State<RootAuthWrapper> createState() => _RootAuthWrapperState();
}

class _RootAuthWrapperState extends State<RootAuthWrapper> {
  bool _isAuthenticated = false;

  void _login() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  void _logout() {
    setState(() {
      _isAuthenticated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return MainNavigation(
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
        onLogout: _logout,
      );
    }

    return LoginScreen(onLogin: _login);
  }
}
