import 'package:flutter/material.dart';
import '../theme/checkmate_theme.dart';
import '../widgets/motion.dart';
import 'profile_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onLogout;
  final VoidCallback onProfileUpdated;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onLogout,
    required this.onProfileUpdated,
  });

  Widget _section(BuildContext context, String label, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
          child: Text(label.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(letterSpacing: 1.1)),
        ),
        Card(
          child: Column(children: [
            for (final (i, tile) in tiles.indexed) ...[
              if (i > 0) const Divider(indent: 68),
              tile,
            ],
          ]),
        ),
      ],
    );
  }

  Widget _iconTile(BuildContext context, IconData icon) {
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: accent, size: 21),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if the current theme is actually dark (works for system, light, or dark modes)
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final error = Theme.of(context).colorScheme.error;

    final sections = [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        child:
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
      ),
      _section(context, 'Appearance', [
        SwitchListTile(
          title: const Text('Dark Mode'),
          subtitle: const Text('Toggle between light and dark themes'),
          value: isDarkMode,
          onChanged: onThemeChanged,
          secondary: AnimatedSwitcher(
            duration: CheckMateTheme.medium,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                RotationTransition(
                    turns: animation,
                    child: ScaleTransition(scale: animation, child: child)),
            child: KeyedSubtree(
              key: ValueKey<bool>(isDarkMode),
              child: _iconTile(
                  context, isDarkMode ? Icons.dark_mode : Icons.light_mode),
            ),
          ),
        ),
      ]),
      _section(context, 'Account', [
        ListTile(
          leading: _iconTile(context, Icons.person_outline),
          title: const Text('Profile Settings'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileSettingsScreen(),
              ),
            );
            if (result != null) {
              onProfileUpdated();
            }
          },
        ),
        ListTile(
          leading: _iconTile(context, Icons.lock_outline),
          title: const Text('Privacy & Security'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ]),
      _section(context, 'About', [
        ListTile(
          leading: _iconTile(context, Icons.info_outline),
          title: const Text('App Version'),
          trailing: const Text('1.0.1'),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Pressable(
          child: OutlinedButton.icon(
            onPressed: onLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: error,
              side: BorderSide(color: error.withValues(alpha: 0.4)),
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
          ),
        ),
      ),
    ];

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              for (final (i, section) in sections.indexed)
                Reveal(index: i, child: section),
            ],
          ),
        ),
      ),
    );
  }
}
