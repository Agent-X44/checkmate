import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/image_processor.dart';
import 'screens/root_auth_wrapper.dart';

List<CameraDescription> globalCameras = [];

/// CheckMate: Secure AI Learning Management System
/// 
/// Official name: CheckMate
/// Branding: Blue (Light Mode) / Yellow (Dark Mode)
/// Standard Corners: 16px
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ssfzrtenhiaiumxmuabq.supabase.co',
    anonKey: 'sb_publishable_RySftOBho4GUXi4k1i4V6g_rhAjVBha',
  );

  try {
    globalCameras = await availableCameras();
    debugPrint("OpenCV Status: ${ImageProcessor.getOpenCVVersion()}");
  } catch (e) {
    debugPrint("App initialization error: $e");
  }

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
      // Use bool for simple binary toggle, but default to system if not set
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
    const Color primaryBlue = Color(0xFF1A237E);
    const Color accentYellow = Color(0xFFFFEB3B);

    return MaterialApp(
      title: 'CheckMate',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          onPrimary: Colors.white,
          secondary: accentYellow,
          onSecondary: Colors.black,
          brightness: Brightness.light,
          onSurface: Colors.black,
          onSurfaceVariant: Colors.black54,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
          bodySmall: TextStyle(color: Colors.black54),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(color: Colors.grey),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primaryBlue)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          onPrimary: Colors.white,
          secondary: accentYellow,
          onSecondary: Colors.black,
          brightness: Brightness.dark,
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white70,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: accentYellow, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(color: accentYellow, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: accentYellow, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(color: Colors.white70),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentYellow)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: RootAuthWrapper(
        themeMode: _themeMode,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}
