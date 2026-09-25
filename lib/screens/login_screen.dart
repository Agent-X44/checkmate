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
      CheckMateUi.showTopPrompt(
          context, 'Please agree to the Terms and Conditions.');
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
        CheckMateUi.showTopPrompt(
            context, 'Authentication failed. Check your credentials.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showTermsDialog(BuildContext context, Color accentColor,
      bool isDark, Color textColor) async {
    bool agreed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool localAgreed = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              title: Text('Terms and Conditions',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Welcome to CheckMate LMS.\n\n'
                      'By creating an account or signing in with Google, you agree to comply with and be bound by the following terms and conditions of use, which govern CheckMate LMS relationship with you in relation to this educational platform.\n\n'
                      '1. Data Privacy & Security: Your grading data, optical mark recognition (OMR) scans, and academic records are securely processed and protected in compliance with educational privacy standards.\n'
                      '2. User Conduct: You agree to use this platform solely for legitimate academic and educational assessment purposes.\n'
                      '3. Local Processing: OMR grading is executed locally on your device to ensure privacy and efficiency.\n\n'
                      'Please review these terms carefully before proceeding.',
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.8),
                          height: 1.4,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: Text('I agree to the Terms & Conditions',
                          style: TextStyle(fontSize: 13, color: textColor)),
                      value: localAgreed,
                      onChanged: (val) =>
                          setDialogState(() => localAgreed = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style:
                          TextStyle(color: textColor.withValues(alpha: 0.7))),
                ),
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
                  child: const Text('Continue',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
    if (!mounted) return;
    final hasAgreed = prefs.getBool('agreed_to_terms') ?? false;

    if (!hasAgreed) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final accentColor =
          isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
      final textColor = isDark ? Colors.white : Colors.black;

      final agreed =
          await _showTermsDialog(context, accentColor, isDark, textColor);
      if (!mounted || !agreed) return;
      await prefs.setBool('agreed_to_terms', true);
    }

    if (!mounted) return;
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
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 360 ? 20 : 28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          sin(_shakeAnimation.value * pi * 4) * 8,
                          0,
                        ),
                        child: child,
                      ),
                      child: _buildAuthForm(
                        theme: theme,
                        isDark: isDark,
                        accentColor: accentColor,
                        buttonTextColor: buttonTextColor,
                      ),
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

  Widget _buildAuthForm({
    required ThemeData theme,
    required bool isDark,
    required Color accentColor,
    required Color buttonTextColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            'assets/checkmate.png',
            width: 96,
            height: 96,
            color: accentColor,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'CheckMate LMS',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(color: accentColor),
        ),
        const SizedBox(height: 32),
        Text(
          _isLoginMode ? 'Welcome back' : 'Create your account',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isLoginMode
              ? 'Sign in to continue to your classes.'
              : 'Get started with your classes and assessments.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 28),
        if (!_isLoginMode) ...[
          _buildField(
            controller: _nameController,
            label: 'Full name',
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
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 20),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        if (!_isLoginMode) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _agreedToTerms,
                activeColor: accentColor,
                onChanged: (val) =>
                    setState(() => _agreedToTerms = val ?? false),
              ),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final agreed = await _showTermsDialog(
                      context,
                      accentColor,
                      isDark,
                      theme.colorScheme.onSurface,
                    );
                    if (agreed && mounted) {
                      setState(() => _agreedToTerms = true);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'I agree to the Terms and Conditions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleAuth,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: accentColor,
            foregroundColor: buttonTextColor,
          ),
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: buttonTextColor,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _isLoginMode ? 'Log in' : 'Sign up',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _handleGoogleSignIn,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: theme.colorScheme.onSurface,
          ),
          icon: Icon(Icons.login, size: 20, color: accentColor),
          label: const Text('Continue with Google'),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            setState(() {
              _isLoginMode = !_isLoginMode;
              _emailError = false;
              _passwordError = false;
              _nameError = false;
            });
          },
          child: Text(
            _isLoginMode
                ? "Don't have an account? Sign up"
                : 'Already have an account? Log in',
            textAlign: TextAlign.center,
          ),
        ),
      ],
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
        labelStyle: TextStyle(
            color: hasError
                ? Colors.red
                : (isDark ? Colors.white70 : Colors.grey)),
        floatingLabelStyle:
            TextStyle(color: hasError ? Colors.red : accentColor),
        prefixIcon: Icon(icon,
            color:
                hasError ? Colors.red : (isDark ? Colors.white70 : Colors.grey),
            size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: hasError
            ? Colors.red.withValues(alpha: 0.05)
            : (isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: hasError
                  ? Colors.red
                  : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: hasError
                  ? Colors.red
                  : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: hasError ? Colors.red : accentColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}
