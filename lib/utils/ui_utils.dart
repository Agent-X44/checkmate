import 'package:flutter/material.dart';

class CheckMateUi {
  /// Shows a subtle, brand-aligned prompt at the top of the screen.
  static void showTopPrompt(BuildContext context, String message, {bool isError = true}) {
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Brand colors: Blue in Light Mode, Yellow in Dark Mode
    final backgroundColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final textColor = isDark ? Colors.black : Colors.white;

    final friendlyMessage = _getFriendlyMessage(message);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _TopPromptWidget(
        message: friendlyMessage,
        backgroundColor: backgroundColor,
        textColor: textColor,
        onDismiss: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
        },
      ),
    );

    overlay.insert(overlayEntry);
  }

  static String _getFriendlyMessage(String technical) {
    final low = technical.toLowerCase();
    
    // Auth Errors
    if (low.contains('invalid login credentials') || low.contains('invalid-credential')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (low.contains('user already exists') || low.contains('email-already-in-use')) {
      return 'An account with this email already exists.';
    }
    if (low.contains('weak-password')) {
      return 'Password is too weak. Try a longer one.';
    }
    
    // Network Errors
    if (low.contains('network') || low.contains('socketexception') || low.contains('connection failed')) {
      return 'Connection lost. Please check your internet.';
    }
    if (low.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    }
    
    // Database/General Errors
    if (low.contains('permission-denied') || low.contains('insufficient-permission') || low.contains('violates row-level security')) {
      return 'Access denied. You may not have permission to perform this action.';
    }
    if (low.contains('violates foreign key constraint') || low.contains('key is not present in table')) {
      return 'Account setup incomplete. Synchronizing your profile... Please try again in a moment.';
    }
    if (low.contains('class not found') || low.contains('invalid code') || low.contains('no rows')) {
      return 'Course code invalid. Please check and try again.';
    }
    if (low.contains('cannot join as a student') || low.contains('owner cannot enroll')) {
      return 'You created this course. You cannot join it as a student.';
    }
    if (low.contains('not found')) {
      return 'The requested resource was not found.';
    }

    // Default: Clean up technical prefixes if any
    return technical.replaceAll(RegExp(r'^Exception: '), '').replaceAll(RegExp(r'^Error: '), '');
  }

  /// Generates a consistent gradient based on a unique ID (e.g. user ID or course ID).
  /// - Light Mode: Bright, rich, highly saturated vibrant tones that pop with energetic chroma.
  /// - Dark Mode: Lighter, soft, desaturated luminous tones that provide eye comfort on dark backgrounds.
  /// Guarantees that the base color family for a given ID stays IDENTICAL across both Light Mode and Dark Mode.
  static List<Color> generateGradient(String id, {bool isDark = false}) {
    final int hash = id.hashCode.abs();
    // High-entropy Murmur-inspired bit mixer to spread out similar UUIDs across the 16 presets
    final int mixedHash = ((hash ^ (hash >> 16)) * 0x45d9f3b) & 0x7FFFFFFF;
    final int index = mixedHash % 16;

    if (isDark) {
      // Dark Mode: Lighter, soft, desaturated, soothing luminous tones
      final List<List<Color>> darkDesaturated = [
        [const Color(0xFF90CAF9), const Color(0xFF80DEEA)], // 0. Soft Periwinkle -> Ice Cyan
        [const Color(0xFF80CBC4), const Color(0xFFA5D6A7)], // 1. Muted Teal -> Soft Sage
        [const Color(0xFFB39DDB), const Color(0xFFE1BEE7)], // 2. Desaturated Lilac -> Pastel Lavender
        [const Color(0xFFCE93D8), const Color(0xFFF48FB1)], // 3. Soft Orchid -> Soft Pink
        [const Color(0xFFFF8A65), const Color(0xFFFFD180)], // 4. Soft Coral -> Muted Peach
        [const Color(0xFFFFCC80), const Color(0xFFFFF59D)], // 5. Soft Warm Gold -> Pastel Yellow
        [const Color(0xFF81C784), const Color(0xFFDCE775)], // 6. Soft Emerald -> Muted Lime
        [const Color(0xFF80DEEA), const Color(0xFF80D8FF)], // 7. Soft Aqua -> Light Sky
        [const Color(0xFFB2DFDB), const Color(0xFFC8E6C9)], // 8. Soft Foam -> Muted Mint
        [const Color(0xFFFFAB91), const Color(0xFFFFCC80)], // 9. Muted Apricot -> Soft Gold
        [const Color(0xFFB0BEC5), const Color(0xFFCFD8DC)], // 10. Soft Slate -> Light Steel
        [const Color(0xFF9FA8DA), const Color(0xFFB39DDB)], // 11. Soft Indigo -> Desaturated Violet
        [const Color(0xFFC5CAE9), const Color(0xFFE0F7FA)], // 12. Pastel Periwinkle -> Ice Cyan
        [const Color(0xFFFF80AB), const Color(0xFFFF8A65)], // 13. Soft Rose -> Muted Coral
        [const Color(0xFFAED581), const Color(0xFFFFF176)], // 14. Soft Lime -> Soft Yellow
        [const Color(0xFFB3E5FC), const Color(0xFFC8E6C9)], // 15. Light Powder Blue -> Soft Mint
      ];
      return darkDesaturated[index];
    } else {
      // Light Mode: Bright, punchy, rich, highly saturated vibrant tones
      final List<List<Color>> lightSaturated = [
        [const Color(0xFF1976D2), const Color(0xFF00ACC1)], // 0. Vibrant Royal Blue -> Bright Cyan
        [const Color(0xFF00897B), const Color(0xFF43A047)], // 1. Rich Emerald Teal -> Bright Green
        [const Color(0xFF5E35B1), const Color(0xFF8E24AA)], // 2. Vivid Violet -> Rich Purple
        [const Color(0xFFD81B60), const Color(0xFFE91E63)], // 3. Punchy Crimson -> Bright Magenta
        [const Color(0xFFF4511E), const Color(0xFFFB8C00)], // 4. Vibrant Coral -> Energetic Orange
        [const Color(0xFFFF8F00), const Color(0xFFFFC107)], // 5. Rich Amber -> Vibrant Gold
        [const Color(0xFF2E7D32), const Color(0xFF7CB342)], // 6. Vibrant Forest -> Bright Lime Green
        [const Color(0xFF0288D1), const Color(0xFF00BFA5)], // 7. Vivid Cerulean -> Bright Teal
        [const Color(0xFF00838F), const Color(0xFF00E676)], // 8. Rich Cyan -> Electric Green
        [const Color(0xFFE64A19), const Color(0xFFFF6D00)], // 9. Punchy Terracotta -> Bright Amber
        [const Color(0xFF4527A0), const Color(0xFF7B1FA2)], // 10. Deep Royal Purple -> Vivid Orchid
        [const Color(0xFFC2185B), const Color(0xFFFF4081)], // 11. Vivid Rose -> Bright Pink
        [const Color(0xFF1565C0), const Color(0xFF0288D1)], // 12. Rich Sapphire -> Vibrant Blue
        [const Color(0xFFD84315), const Color(0xFFFF9100)], // 13. Vibrant Rust -> Bright Orange
        [const Color(0xFF283593), const Color(0xFF00897B)], // 14. Deep Indigo -> Rich Teal
        [const Color(0xFF33691E), const Color(0xFF64DD17)], // 15. Deep Leaf -> Bright Neon Lime
      ];
      return lightSaturated[index];
    }
  }
}

class _TopPromptWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onDismiss;

  const _TopPromptWidget({
    required this.message,
    required this.backgroundColor,
    required this.textColor,
    required this.onDismiss,
  });

  @override
  State<_TopPromptWidget> createState() => _TopPromptWidgetState();
}

class _TopPromptWidgetState extends State<_TopPromptWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _offset = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _offset,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor.withValues(alpha: 0.7), // Increased transparency for subtlety
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
