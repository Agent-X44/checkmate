import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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
  bool _isInitDone = false;

  @override
  void initState() {
    super.initState();
    _initEngineAndAuth();
  }

  Future<void> _initEngineAndAuth() async {
    try {
      // Parallel fast initialization of Supabase engine
      await Supabase.initialize(
        url: 'https://ssfzrtenhiaiumxmuabq.supabase.co',
        publishableKey: 'sb_publishable_RySftOBho4GUXi4k1i4V6g_rhAjVBha',
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _user = Supabase.instance.client.auth.currentUser;
        _isInitDone = true;
      });
      _setupAuthListener();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      precacheImage(const AssetImage('assets/checkmate.png'), context);
    } catch (_) {}
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
    if (!_isInitDone) {
      return const SizedBox.shrink(); // Native splash remains preserved over this brief frame
    }

    // Dismiss native splash cleanly as soon as target screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });

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
