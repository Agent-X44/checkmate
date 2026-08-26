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
                    color: widget.backgroundColor.withOpacity(0.85), // Reverted to withOpacity for stability
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
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
