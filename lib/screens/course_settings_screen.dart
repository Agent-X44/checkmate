import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

/// Screen for course-specific configuration, invitation codes, QR sharing, and deletion.
/// Enforces:
/// - BR-01: Course Management & Invitation Code Settings
class CourseSettingsScreen extends StatefulWidget {
  final Course course;
  final VoidCallback onDelete;

  const CourseSettingsScreen({
    super.key,
    required this.course,
    required this.onDelete,
  });

  @override
  State<CourseSettingsScreen> createState() => _CourseSettingsScreenState();
}

class _CourseSettingsScreenState extends State<CourseSettingsScreen> {
  late String _currentJoinCode;

  @override
  void initState() {
    super.initState();
    _currentJoinCode = widget.course.joinCode;
  }

  void _copyLink() {
    final link = "https://checkmate.app/join?code=$_currentJoinCode";
    Clipboard.setData(ClipboardData(text: link));
    CheckMateUi.showTopPrompt(context, 'Invitation link copied to clipboard!', isError: false);
  }

  void _showQrDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Course QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  data: _currentJoinCode,
                  version: QrVersions.auto,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Code: $_currentJoinCode', 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              )
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text('CLOSE', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  Future<void> _resetCode() async {
    try {
      final newCode = await SupabaseService.resetCourseCode(widget.course.id);
      setState(() {
        _currentJoinCode = newCode;
      });
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Course code reset successfully!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Failed to reset code: $e');
      }
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text(
            'Are you sure you want to permanently delete "${widget.course.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              try {
                await SupabaseService.deleteClass(widget.course.id);
                if (context.mounted) {
                  CheckMateUi.showTopPrompt(context, 'Course deleted successfully', isError: false);
                  widget.onDelete(); // Trigger actual deletion logic
                  Navigator.pop(context); // Return to Dashboard
                }
              } catch (e) {
                if (context.mounted) {
                  CheckMateUi.showTopPrompt(context, 'Delete failed: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = widget.course.adaptiveGradient(context);
    final contentColor = isDark ? const Color(0xFF141318) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'General',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Course Name'),
            subtitle: Text(widget.course.name),
            trailing: const Icon(Icons.edit, size: 20),
          ),
          const Divider(height: 32),
          const Text(
            'Invitation Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Invitation Code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: contentColor.withValues(alpha: 0.8),
                          )),
                      SelectableText(
                        _currentJoinCode,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: contentColor,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildInviteAction(
                          context, Icons.link, 'Copy Link', contentColor, _copyLink),
                      _buildInviteAction(
                          context, Icons.qr_code_2, 'Show QR', contentColor, _showQrDialog),
                      _buildInviteAction(
                          context, Icons.refresh, 'Reset Code', contentColor, _resetCode),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Danger Zone',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete Course',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text(
                'Once deleted, all data is permanent and cannot be undone.'),
            onTap: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteAction(
      BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withAlpha(200)),
        ),
      ],
    );
  }
}
