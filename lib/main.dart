import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'services/image_processor.dart';
import 'screens/root_auth_wrapper.dart';

List<CameraDescription> globalCameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    globalCameras = await availableCameras();
    debugPrint("OpenCV Status: ${ImageProcessor.getOpenCVVersion()}");
  } catch (e) {
    debugPrint("App initialization error: $e");
  }

  runApp(const CheckmateApp());
}

class CheckmateApp extends StatefulWidget {
  const CheckmateApp({super.key});

  @override
  State<CheckmateApp> createState() => _CheckmateAppState();
}

class _CheckmateAppState extends State<CheckmateApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDarkMode = prefs.getBool('isDarkMode') ?? false;
      if (mounted) {
        setState(() {
          _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
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
      title: 'Checkmate',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentYellow,
          brightness: Brightness.light,
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
          secondary: accentYellow,
          brightness: Brightness.dark,
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
