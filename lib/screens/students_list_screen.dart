import 'package:flutter/material.dart';
import '../models/course.dart';
import 'private_chat_screen.dart';

class StudentsListScreen extends StatefulWidget {
  final Course course;
  const StudentsListScreen({super.key, required this.course});

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: [
          if (widget.course.isOwner)
            Row(
              children: [
                const Text('Replies', style: TextStyle(fontSize: 12)),
                Switch(
                  value: widget.course.globalCanStudentReply,
                  onChanged: (value) {
                    setState(() {
                      widget.course.globalCanStudentReply = value;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value
                            ? 'Students can now reply to private messages.'
                            : 'Student replies have been disabled.'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  activeThumbColor: Colors.yellowAccent,
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.course.isOwner)
            Container(
              padding: const EdgeInsets.all(12),
              color:
                  Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Use the switch above to enable or disable private message replies for all students.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.course.enrolledStudents.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final student = widget.course.enrolledStudents[index];

                // Determine if messaging is allowed (only for the course owner/teacher)
                final bool canMessage = widget.course.isOwner;

                return Card(
                  elevation: 0,
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CircleAvatar(
                      child: Text(student.avatar),
                    ),
                    title: Text(student.name),
                    subtitle: const Text('Regular Student'),
                    // Only show message icon and enable tap if the user is the teacher
                    trailing: canMessage
                        ? const Icon(Icons.message,
                            size: 20, color: Colors.blue)
                        : null,
                    onTap: canMessage
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PrivateChatScreen(
                                  course: widget.course,
                                  student: student,
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
