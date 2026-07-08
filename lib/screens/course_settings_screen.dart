import 'package:flutter/material.dart';
import '../models/course.dart';

class CourseSettingsScreen extends StatelessWidget {
  final Course course;
  final VoidCallback onDelete;

  const CourseSettingsScreen({
    super.key, 
    required this.course,
    required this.onDelete,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text('Are you sure you want to permanently delete ${course.code}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), 
            child: const Text('CANCEL')
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              onDelete(); // Trigger actual deletion logic
              Navigator.pop(context); // Return to Dashboard
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
            title: const Text('Course Code'),
            subtitle: Text(course.code),
            trailing: const Icon(Icons.edit, size: 20),
          ),
          ListTile(
            title: const Text('Course Name'),
            subtitle: Text(course.name),
            trailing: const Icon(Icons.edit, size: 20),
          ),
          const Divider(height: 32),
          const Text(
            'Invitation Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          // MODIFIED: Specific styling for high visibility in Dark Mode
          Card(
            color: Theme.of(context).colorScheme.primary, // Using primary color (Deep Blue) for the card
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Join Code', 
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          color: Colors.white70, // White text
                        )
                      ),
                      SelectableText(
                        course.joinCode,
                        style: const TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // Bright white for code
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildInviteAction(context, Icons.link, 'Copy Link', Colors.white),
                      _buildInviteAction(context, Icons.qr_code_2, 'Show QR', Colors.white),
                      _buildInviteAction(context, Icons.refresh, 'Reset Code', Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Danger Zone',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete Course', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Once deleted, all data is permanent and cannot be undone.'),
            onTap: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteAction(BuildContext context, IconData icon, String label, Color color) {
    return Column(
      children: [
        IconButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label feature coming soon!')));
          },
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
