import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The original CheckMate palette, with shared mobile component styles.
abstract final class CheckMateTheme {
  static const blue = Color(0xFF1A237E);
  static const yellow = Color(0xFFFFEB3B);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = dark ? yellow : blue;
    final onAccent = dark ? Colors.black : Colors.white;
    final background = dark ? const Color(0xFF121212) : const Color(0xFFF7F7F7);
    final surface = dark ? const Color(0xFF1E1E24) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF191919);
    final muted = dark ? Colors.white60 : Colors.black54;
    final outline = dark ? const Color(0xFF37373D) : const Color(0xFFE8E8E8);
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
    ).copyWith(
      primary: blue,
      onPrimary: Colors.white,
      secondary: yellow,
      onSecondary: Colors.black,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer:
          dark ? const Color(0xFF242429) : const Color(0xFFF2F2F2),
      surfaceContainerHigh:
          dark ? const Color(0xFF2A2A30) : const Color(0xFFEFEFEF),
      surfaceContainerHighest:
          dark ? const Color(0xFF303036) : const Color(0xFFEAEAEA),
      outline: outline,
      outlineVariant: outline,
      surfaceTint: Colors.transparent,
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final button = ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: onAccent,
      minimumSize: const Size(48, 50),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      elevation: 0,
      shape: shape,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      dividerColor: outline,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            color: text,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8),
        headlineMedium: TextStyle(
            color: text,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6),
        headlineSmall: TextStyle(
            color: text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4),
        titleLarge:
            TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium:
            TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall:
            TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: text, fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(color: text, fontSize: 14, height: 1.4),
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.4),
        labelLarge:
            TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF121212) : blue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
          color: surface, elevation: 0, margin: EdgeInsets.zero, shape: shape),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF252529) : const Color(0xFFF0F0F0),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accent, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: outline),
        shape: shape,
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: accent)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: shape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : muted,
              size: 24,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? accent : muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        dividerColor: outline,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onAccent : null),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : null),
      ),
      listTileTheme: ListTileThemeData(
          iconColor: muted,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      dividerTheme: DividerThemeData(color: outline, thickness: 0.7, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
    );
  }
}
