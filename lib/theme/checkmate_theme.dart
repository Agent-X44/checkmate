import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The original CheckMate palette (blue light / yellow dark) with modern
/// component shapes and app-wide motion.
abstract final class CheckMateTheme {
  static const blue = Color(0xFF1A237E);
  static const blueDeep = Color(0xFF0D1457);
  static const blueBright = Color(0xFF3949AB);
  static const yellow = Color(0xFFFFEB3B);

  /// Brand gradient used on hero surfaces.
  static const brandGradient = LinearGradient(
    colors: [blueBright, blue, blueDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Motion tokens: micro-interactions are quick, entrances a little slower.
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const emphasized = Curves.easeOutCubic;

  /// Brand accent for the current mode: blue in light, yellow in dark.
  static Color accentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? yellow : blue;

  /// Text/icon color that sits on top of [accentOf].
  static Color onAccentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : Colors.white;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = dark ? yellow : blue;
    final onAccent = dark ? Colors.black : Colors.white;
    final background = dark ? const Color(0xFF0F0F14) : const Color(0xFFF5F6FB);
    final surface = dark ? const Color(0xFF1A1A21) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF14152B);
    final muted = dark ? Colors.white60 : const Color(0xFF5E6178);
    final outline = dark ? const Color(0xFF2E2E37) : const Color(0xFFE4E6F0);
    final field = dark ? const Color(0xFF22222A) : const Color(0xFFF0F1F7);
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
          dark ? const Color(0xFF202027) : const Color(0xFFF0F1F7),
      surfaceContainerHigh:
          dark ? const Color(0xFF26262E) : const Color(0xFFEBECF4),
      surfaceContainerHighest:
          dark ? const Color(0xFF2C2C35) : const Color(0xFFE5E7F0),
      outline: outline,
      outlineVariant: outline,
      surfaceTint: Colors.transparent,
    );
    const pill = StadiumBorder();
    const buttonText = TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1);
    final button = ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: onAccent,
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      elevation: 0,
      shape: pill,
      textStyle: buttonText,
      animationDuration: fast,
    );
    TextStyle style(double size, FontWeight weight,
            {double spacing = 0, double? height, Color? color}) =>
        TextStyle(
            color: color ?? text,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: spacing,
            height: height);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: outline,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final platform in TargetPlatform.values)
          platform: platform == TargetPlatform.iOS ||
                  platform == TargetPlatform.macOS
              ? const CupertinoPageTransitionsBuilder()
              : FadeForwardsPageTransitionsBuilder(backgroundColor: background),
      }),
      textTheme: TextTheme(
        displaySmall: style(36, FontWeight.w800, spacing: -1.2),
        headlineLarge: style(32, FontWeight.w800, spacing: -1),
        headlineMedium: style(28, FontWeight.w800, spacing: -0.8),
        headlineSmall: style(24, FontWeight.w800, spacing: -0.6),
        titleLarge: style(20, FontWeight.w700, spacing: -0.3),
        titleMedium: style(16, FontWeight.w700, spacing: -0.1),
        titleSmall: style(14, FontWeight.w600),
        bodyLarge: style(16, FontWeight.w400, height: 1.5),
        bodyMedium: style(14, FontWeight.w400, height: 1.45),
        bodySmall: style(12, FontWeight.w400, height: 1.4, color: muted),
        labelLarge: style(14, FontWeight.w700),
        labelMedium: style(12, FontWeight.w600, spacing: 0.2),
        labelSmall: style(11, FontWeight.w600, spacing: 0.4, color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? background : blue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: accent),
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: outline.withValues(alpha: 0.6))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accent, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: scheme.error)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.25),
        selectionHandleColor: accent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        side: BorderSide(color: outline, width: 1.5),
        shape: pill,
        textStyle: buttonText,
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(48, 44),
        shape: pill,
        textStyle: buttonText,
      )),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 3,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        extendedTextStyle: buttonText,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: dark ? 0.18 : 0.12),
        indicatorShape: pill,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : muted,
              size: 24,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? accent : muted,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: accent, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        showCheckmark: false,
        side: WidgetStateBorderSide.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? BorderSide(color: accent, width: 1.5)
                : BorderSide(color: outline)),
        color: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? accent.withValues(alpha: dark ? 0.16 : 0.1)
                : surface),
        iconTheme: IconThemeData(color: accent, size: 18),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: accent,
          selectedForegroundColor: onAccent,
          side: BorderSide(color: outline),
          shape: pill,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: accent.withValues(alpha: 0.12),
        circularTrackColor: Colors.transparent,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
      switchTheme: SwitchThemeData(
        // Explicit off-state colors: the defaults vanish on white cards.
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onAccent : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : field),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.transparent : muted),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStatePropertyAll(onAccent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : muted),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: style(15, FontWeight.w600),
        subtitleTextStyle: style(13, FontWeight.w400, color: muted),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: style(20, FontWeight.w800, spacing: -0.3),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
        ),
        textStyle: style(14, FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF2C2C35) : const Color(0xFF14152B),
        contentTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: yellow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2C2C35) : const Color(0xFF14152B),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
      ),
    );
  }
}
