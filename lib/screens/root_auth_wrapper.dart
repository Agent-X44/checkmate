import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

class RootAuthWrapper extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(bool) onThemeChanged;

  const RootAuthWrapper({
    super.key, 
    required this.themeMode, 
    required this.onThemeChanged
  });

  @override
  State<RootAuthWrapper> createState() => _RootAuthWrapperState();
}

class _RootAuthWrapperState extends State<RootAuthWrapper> {
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = Supabase.instance.client.auth.currentUser;
    _setupAuthListener();
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _user = data.session?.user;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null) {
      return MainNavigation(
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
        onLogout: () async {
          await SupabaseService.signOut();
        },
      );
    }

    return const LoginScreen();
  }
}
