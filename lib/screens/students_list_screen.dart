import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

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
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SupabaseService.getEnrolledStudents(widget.course.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final studentsData = snapshot.data ?? [];
          if (studentsData.isEmpty) {
            return const Center(child: Text("No students enrolled yet."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: studentsData.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final profile = studentsData[index]['profiles'] as Map;
              final name = profile['name'] ?? 'Student';
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return Card(
                elevation: 0,
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    child: Text(initial),
                  ),
                  title: Text(name),
                  subtitle: const Text('Enrolled'),
                  trailing: widget.course.isOwner
                      ? const Icon(Icons.message, size: 20, color: Colors.blue)
                      : null,
                  onTap: widget.course.isOwner
                      ? () {
                          // Messaging logic (mocked for demo)
                          CheckMateUi.showTopPrompt(context, "Messaging system coming soon!", isError: false);
                        }
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
