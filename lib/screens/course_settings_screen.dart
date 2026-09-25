import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../services/deep_link_service.dart';
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
    // Web invitation link feature commented out until web host is deployed
    /*
    final link = DeepLinkService.buildInviteLink(_currentJoinCode);
    Clipboard.setData(ClipboardData(text: link));
    CheckMateUi.showTopPrompt(context, 'Invitation link copied to clipboard!', isError: false);
    */
    CheckMateUi.showTopPrompt(
      context,
      'Invitation links coming soon! Share Course Code: $_currentJoinCode',
      isError: false,
    );
  }

  void _shareInviteLink() {
    // Web invitation link feature commented out until web host is deployed
    /*
    final link = DeepLinkService.buildInviteLink(_currentJoinCode);
    final text = 'Join my course "${widget.course.name}" on CheckMate!\n\nLink: $link\nCourse Code: $_currentJoinCode';
    Share.shareXFiles([], text: text);
    */
    CheckMateUi.showTopPrompt(
      context,
      'Invitation links coming soon! Share Course Code: $_currentJoinCode',
      isError: false,
    );
  }

  void _showQrDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final qrData = DeepLinkService.buildCustomSchemeLink(_currentJoinCode);
    final qrSize = (MediaQuery.sizeOf(context).width - 152).clamp(80.0, 200.0);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
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
                width: qrSize,
                height: qrSize,
                child: QrImageView(
                  data: qrData,
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
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              CheckMateUi.showTopPrompt(
                context,
                'Invitation links coming soon! Use Course Code: $_currentJoinCode',
                isError: false,
              );
            },
            child: Text('COPY LINK', style: TextStyle(color: accentColor)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CLOSE',
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _resetCode() async {
    try {
      final newCode = await SupabaseService.resetCourseCode(widget.course.id);
      if (!mounted) return;
      setState(() {
        _currentJoinCode = newCode;
      });
      CheckMateUi.showTopPrompt(context, 'Course code reset successfully!',
          isError: false);
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
              child:
                  const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              try {
                await SupabaseService.deleteClass(widget.course.id);
                if (context.mounted) {
                  CheckMateUi.showTopPrompt(
                      context, 'Course deleted successfully',
                      isError: false);
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? colors.secondary : colors.primary;
    final inviteBackground =
        dark ? colors.surfaceContainerHigh : colors.primary;
    final inviteForeground = dark ? colors.onSurface : colors.onPrimary;

    return Scaffold(
      appBar: AppBar(title: const Text('Course settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Text('General',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  leading: Icon(Icons.school_outlined, color: accent),
                  title: const Text('Course name'),
                  subtitle: Text(widget.course.name,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 30),
              Text('Invitation settings',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: inviteBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Course code',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: inviteForeground.withValues(alpha: 0.8),
                        )),
                    const SizedBox(height: 6),
                    SelectableText(
                      _currentJoinCode,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: inviteForeground,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actionWidth =
                            constraints.maxWidth >= 520 ? 112.0 : 105.0;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildInviteAction(
                                Icons.share_outlined,
                                'Share',
                                inviteForeground,
                                _shareInviteLink,
                                actionWidth),
                            _buildInviteAction(Icons.link, 'Copy link',
                                inviteForeground, _copyLink, actionWidth),
                            _buildInviteAction(Icons.qr_code_2, 'Show QR',
                                inviteForeground, _showQrDialog, actionWidth),
                            _buildInviteAction(Icons.refresh, 'Reset code',
                                inviteForeground, _resetCode, actionWidth),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text('Danger zone',
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: colors.error)),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  leading:
                      Icon(Icons.delete_forever_outlined, color: colors.error),
                  title: Text('Delete course',
                      style: TextStyle(
                          color: colors.error, fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Permanently delete this course and its data.'),
                  trailing: Icon(Icons.chevron_right, color: colors.error),
                  onTap: () => _confirmDelete(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteAction(IconData icon, String label, Color color,
      VoidCallback onTap, double width) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
