import 'dart:math';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

/// Entry screen for Authentication (Email/Password and Google Sign-In).
/// Features: Adaptive theming, shake animations for validation, and Hero transitions.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLoginMode = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

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
    _shakeController.forward(from: 0.0);
  }

  Future<void> _handleAuth() async {
    // 1. Reset Errors
    setState(() {
      _emailError = _emailController.text.trim().isEmpty;
      _passwordError = _passwordController.text.trim().isEmpty;
      if (!_isLoginMode) {
        _nameError = _nameController.text.trim().isEmpty;
      }
    });

    // 2. Validate
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

  Future<void> _handleGoogleSignIn() async {
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
    
    // Explicitly use yellow in dark mode for logo if theme mismatch occurs
    final logoColor = isDark ? const Color(0xFFFFEB3B) : theme.colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Brand Identity
                  Hero(
                    tag: 'logo',
                    child: Image.asset(
                      'assets/checkmate.png',
                      height: 100,
                      color: logoColor,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (context, error, stackTrace) => 
                         Icon(Icons.check_circle_outline, size: 80, color: accentColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('CheckMate', 
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: isDark ? Colors.white : theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    )
                  ),
                  Text('Secure AI Learning Management', 
                    style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 1.2)
                  ),
                  const SizedBox(height: 50),
                  
                  // Input Fields
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
                  
                  const SizedBox(height: 30),
                  
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
          
          // Global Loading Overlay (Semi-transparent)
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(child: null),
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
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // Only apply offset if this specific field has an error
        final double offset = hasError ? sin(_shakeAnimation.value * pi * 4) * 3 : 0;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: accentColor, fontWeight: FontWeight.w500),
        cursorColor: accentColor,
        onChanged: (_) => setState(() {
          _emailError = false;
          _passwordError = false;
          _nameError = false;
        }),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: hasError ? Colors.red : Colors.grey, fontSize: 14),
          floatingLabelStyle: TextStyle(color: hasError ? Colors.red : accentColor),
          prefixIcon: Icon(icon, color: hasError ? Colors.red : null, size: 22),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: hasError ? Colors.red.withValues(alpha: 0.05) : Colors.transparent,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: hasError ? Colors.red : Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: hasError ? Colors.red : accentColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }
}
