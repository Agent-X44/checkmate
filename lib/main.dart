import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/image_processor.dart';
import 'screens/root_auth_wrapper.dart';

List<CameraDescription> globalCameras = [];

final ThemeData _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1A237E),
    primary: const Color(0xFF1A237E),
    onPrimary: Colors.white,
    secondary: const Color(0xFFFFEB3B),
    onSecondary: Colors.black,
    brightness: Brightness.light,
    onSurface: Colors.black,
    onSurfaceVariant: Colors.black54,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold),
    titleLarge: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(color: Colors.black),
    bodyMedium: TextStyle(color: Colors.black),
    bodySmall: TextStyle(color: Colors.black54),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    labelStyle: TextStyle(color: Colors.grey),
    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1A237E))),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1A237E),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
);

final ThemeData _darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1A237E),
    primary: const Color(0xFF1A237E),
    onPrimary: Colors.white,
    secondary: const Color(0xFFFFEB3B),
    onSecondary: Colors.black,
    brightness: Brightness.dark,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white70,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(color: Color(0xFFFFEB3B), fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(color: Color(0xFFFFEB3B), fontWeight: FontWeight.bold),
    titleLarge: TextStyle(color: Color(0xFFFFEB3B), fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(color: Colors.white),
    bodyMedium: TextStyle(color: Colors.white),
    bodySmall: TextStyle(color: Colors.white70),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    labelStyle: TextStyle(color: Colors.white70),
    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFEB3B))),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF121212),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
);

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
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: RootAuthWrapper(
        themeMode: _themeMode,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}
