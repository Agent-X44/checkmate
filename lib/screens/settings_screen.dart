import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: Text(
              'Toggle between light and dark themes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: isDarkMode,
            activeThumbColor: Theme.of(context).colorScheme.secondary,
            onChanged: (bool value) {
              // The parent's setState will trigger a rebuild of the entire app
              onThemeChanged(value);
            },
            secondary: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return RotationTransition(turns: animation, child: child);
              },
              child: Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                key: ValueKey<bool>(isDarkMode),
                color: isDarkMode ? Colors.yellow : Colors.blue,
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Profile Settings'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.lock),
            title: Text('Privacy & Security'),
            trailing: Icon(Icons.chevron_right),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const ListTile(
            title: Text('App Version'),
            trailing: Text('1.0.0'),
          ),
          ListTile(
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            leading: const Icon(Icons.logout, color: Colors.red),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
