import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/image_processor.dart';
import 'services/deep_link_service.dart';
import 'screens/root_auth_wrapper.dart';
import 'theme/checkmate_theme.dart';

List<CameraDescription> globalCameras = [];

/// CheckMate: Secure AI Learning Management System
///
/// Official name: CheckMate
/// Branding: Blue (Light Mode) / Yellow (Dark Mode)
/// Standard Corners: 16px
/// Architecture: Enforces BR-01 through BR-13
void main() {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 1. Unblocked Startup: Load camera hardware & OpenCV asynchronously in background
  availableCameras().then((cams) {
    globalCameras = cams;
  }).catchError((e) {
    debugPrint("Background camera init notice: $e");
  });

  Future.microtask(() {
    try {
      debugPrint("OpenCV Engine: ${ImageProcessor.getOpenCVVersion()}");
    } catch (e) {
      debugPrint("OpenCV init notice: $e");
    }
  });

  // 2. Launch UI immediately (0ms delay before runApp)
  runApp(const CheckMateApp());
}

class CheckMateApp extends StatefulWidget {
  const CheckMateApp({super.key});

  @override
  State<CheckMateApp> createState() => _CheckMateAppState();
}

class _CheckMateAppState extends State<CheckMateApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    DeepLinkService().initialize();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool? isDarkMode = prefs.getBool('isDarkMode');

      if (mounted) {
        setState(() {
          if (isDarkMode == null) {
            _themeMode = ThemeMode.system;
          } else {
            _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
          }
        });
      }
    } catch (e) {
      debugPrint("Theme loading error: $e");
    }
  }

  Future<void> _toggleTheme(bool isDark) async {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', isDark);
    } catch (e) {
      debugPrint("Failed to save theme: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckMate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: CheckMateTheme.light,
      darkTheme: CheckMateTheme.dark,
      home: RootAuthWrapper(
        themeMode: _themeMode,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}
