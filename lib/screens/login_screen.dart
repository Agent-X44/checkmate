import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoginMode = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleAuth() {
    // Both Login and Sign Up lead to the dashboard for simulation
    widget.onLogin();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/checkmate.png',
                height: 100,
                color: isDark ? theme.colorScheme.secondary : null,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.check_circle_outline,
                    size: 100,
                    color: isDark
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.primary,
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Checkmate',
                style: theme.textTheme.headlineLarge,
              ),
              Text(
                'AI-Powered Exam Scanner & LMS',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 40),

              // Animated Switcher for Login/Sign Up Mode Title
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isLoginMode ? 'Welcome Back' : 'Create Account',
                  key: ValueKey<bool>(_isLoginMode),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Sign Up specific field
              if (!_isLoginMode) ...[
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              const SizedBox(height: 30),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark 
                        ? theme.colorScheme.secondary 
                        : theme.colorScheme.primary,
                    foregroundColor: isDark 
                        ? Colors.black 
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _isLoginMode ? 'LOGIN' : 'SIGN UP',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Toggle Mode
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLoginMode = !_isLoginMode;
                  });
                },
                child: Text(
                  _isLoginMode
                      ? "Don't have an account? Sign Up"
                      : "Already have an account? Login",
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
