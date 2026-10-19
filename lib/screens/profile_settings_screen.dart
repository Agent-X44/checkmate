import 'package:flutter/material.dart';
import '../theme/checkmate_theme.dart';
import '../widgets/motion.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final res = await SupabaseService.client
            .from('profiles')
            .select('name')
            .eq('id', user.id)
            .maybeSingle();

        if (res != null && res['name'] != null && mounted) {
          setState(() {
            _nameController.text = res['name'];
          });
        }
      } catch (e) {
        debugPrint("Error loading profile: $e");
      }
    }
  }

  Future<void> _saveProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      CheckMateUi.showTopPrompt(context, "Name cannot be empty.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService.updateProfileName(newName);
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Profile updated successfully!",
            isError: false);
        Navigator.pop(context, newName);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Failed to update profile: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = CheckMateTheme.accentOf(context);
    final onAccent = CheckMateTheme.onAccentOf(context);
    final name = _nameController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Reveal(
                child: Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: accentColor.withValues(alpha: 0.12),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Reveal(
                index: 1,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Display name',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'This is how other users will see you in courses and messages.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Reveal(
                index: 2,
                child: Pressable(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: onAccent),
                          )
                        : const Text('Save changes'),
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
