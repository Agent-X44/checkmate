import 'package:flutter/material.dart';
import 'ai_questionnaire_screen.dart';

class AssignmentsScreen extends StatelessWidget {
  final bool isOwner;
  final String courseId;

  const AssignmentsScreen({
    super.key,
    required this.isOwner,
    required this.courseId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            children: [
              Text('Course assignments',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Keep track of upcoming work and due dates.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 20),
              _buildAssignmentCard(
                  context, 'Assignment 1: Matrix Basics', 'Due: June 20, 2026'),
              _buildAssignmentCard(context, 'Assignment 2: Fourier Transforms',
                  'Due: June 25, 2026'),
              _buildAssignmentCard(context, 'Project Proposal: Signal Filter',
                  'Due: July 05, 2026'),
            ],
          ),
        ),
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AIQuestionnaireScreen(
                      type: 'Assignment',
                      classId: courseId,
                    ),
                  ),
                );
              },
              tooltip: 'Create assignment',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildAssignmentCard(BuildContext context, String title, String due) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent =
        theme.brightness == Brightness.dark ? colors.secondary : colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          child: Icon(Icons.assignment_outlined, color: accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(due),
        trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        onTap: () {},
      ),
    );
  }
}
