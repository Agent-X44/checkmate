import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

/// Entry screen for Authentication (Email/Password and Google Sign-In).
/// Features: Adaptive theming, shake animations for validation, and Hero transitions.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoginMode = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _agreedToTerms = false;

  // Validation States
  bool _emailError = false;
  bool _passwordError = false;
  bool _nameError = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  Future<void> _handleAuth() async {
    // 1. Reset Errors
    setState(() {
      _emailError = _emailController.text.trim().isEmpty;
      _passwordError = _passwordController.text.trim().length < 6;
      _nameError = !_isLoginMode && _nameController.text.trim().isEmpty;
    });

    // 2. Validate Terms for Sign Up
    if (!_isLoginMode && !_agreedToTerms) {
      CheckMateUi.showTopPrompt(context, 'Please agree to the Terms and Conditions.');
      _triggerShake();
      return;
    }

    // 3. Validate Fields
    if (_emailError || _passwordError || (!_isLoginMode && _nameError)) {
      _triggerShake();
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await SupabaseService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await SupabaseService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
        );
        if (mounted) {
          CheckMateUi.showTopPrompt(
            context,
            'Please check your email for confirmation!',
            isError: false,
          );
          setState(() => _isLoginMode = true);
        }
      }
    } catch (e) {
      if (mounted) {
        _triggerShake();
        setState(() {
          _emailError = true;
          _passwordError = true;
        });
        CheckMateUi.showTopPrompt(context, 'Authentication failed. Check your credentials.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showTermsDialog(BuildContext context, Color accentColor, bool isDark, Color textColor) async {
    bool agreed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool localAgreed = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Terms and Conditions', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                height: 300,
                child: SingleChildScrollView(
                  child: Text(
                    'Welcome to CheckMate LMS.\n\n'
                    'By creating an account or signing in with Google, you agree to comply with and be bound by the following terms and conditions of use, which govern CheckMate LMS relationship with you in relation to this educational platform.\n\n'
                    '1. Data Privacy & Security: Your grading data, optical mark recognition (OMR) scans, and academic records are securely processed and protected in compliance with educational privacy standards.\n'
                    '2. User Conduct: You agree to use this platform solely for legitimate academic and educational assessment purposes.\n'
                    '3. Local Processing: OMR grading is executed locally on your device to ensure privacy and efficiency.\n\n'
                    'Please review these terms carefully before proceeding.',
                    style: TextStyle(color: textColor.withValues(alpha: 0.8), height: 1.4, fontSize: 13),
                  ),
                ),
              ),
              actions: [
                CheckboxListTile(
                  title: Text('I agree to the Terms & Conditions', style: TextStyle(fontSize: 12, color: textColor)),
                  value: localAgreed,
                  onChanged: (val) {
                    setDialogState(() {
                      localAgreed = val ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCEL', style: TextStyle(color: textColor.withValues(alpha: 0.7))),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                      ),
                      onPressed: localAgreed
                          ? () {
                              agreed = true;
                              Navigator.pop(context);
                            }
                          : null,
                      child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    return agreed;
  }

  Future<void> _handleGoogleSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAgreed = prefs.getBool('agreed_to_terms') ?? false;

    if (!hasAgreed) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
      final textColor = isDark ? Colors.white : Colors.black;

      final agreed = await _showTermsDialog(context, accentColor, isDark, textColor);
      if (!agreed) return;
      await prefs.setBool('agreed_to_terms', true);
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Google Sign-In failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    // Explicitly use yellow in dark mode for logo, blue in light mode
    final logoColor = isDark ? const Color(0xFFFFEB3B) : theme.colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(sin(_shakeAnimation.value * pi * 4) * 8, 0),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Branding / Logo
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Image.asset(
                        'assets/checkmate.png',
                        width: 150,
                        color: logoColor,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'CheckMate LMS',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoginMode ? 'Welcome back! Please sign in.' : 'Create an account to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Form Fields
                    if (!_isLoginMode) ...[
                      _buildField(
                        controller: _nameController,
                        label: 'Full Name',
                        icon: Icons.person_outline,
                        hasError: _nameError,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 16),
                    ],

                    _buildField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      hasError: _emailError,
                      accentColor: accentColor,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      hasError: _passwordError,
                      accentColor: accentColor,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),

                    if (!_isLoginMode) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: _agreedToTerms,
                            activeColor: accentColor,
                            onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final agreed = await _showTermsDialog(context, accentColor, isDark, isDark ? Colors.white : Colors.black);
                                if (agreed) setState(() => _agreedToTerms = true);
                              },
                              child: Text(
                                'I agree to the Terms and Conditions',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Main Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleAuth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: buttonTextColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: buttonTextColor, strokeWidth: 2))
                          : Text(_isLoginMode ? 'LOGIN' : 'SIGN UP',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(color: Colors.grey, fontSize: 12))),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Social Login
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                        icon: Icon(Icons.login, size: 20, color: accentColor),
                        label: Text("Continue with Google",
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Toggle Mode
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLoginMode = !_isLoginMode;
                          _emailError = false;
                          _passwordError = false;
                          _nameError = false;
                        });
                      },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
                          children: [
                            TextSpan(text: _isLoginMode ? "Don't have an account? " : "Already have an account? "),
                            TextSpan(
                              text: _isLoginMode ? "Sign Up" : "Login",
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool hasError,
    required Color accentColor,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hasError ? Colors.red : (isDark ? Colors.white70 : Colors.grey)),
        floatingLabelStyle: TextStyle(color: hasError ? Colors.red : accentColor),
        prefixIcon: Icon(icon, color: hasError ? Colors.red : (isDark ? Colors.white70 : Colors.grey), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: hasError
            ? Colors.red.withValues(alpha: 0.05)
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : accentColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}
