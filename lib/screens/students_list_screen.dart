import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellow : Colors.blue;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Students', style: TextStyle(color: textColor)),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SupabaseService.getEnrolledStudents(widget.course.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: accentColor));
          }
          
          final studentsData = snapshot.data ?? [];
          if (studentsData.isEmpty) {
            return Center(child: Text("No students enrolled yet.", style: TextStyle(color: textColor.withValues(alpha: 0.6))));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: studentsData.length,
            separatorBuilder: (context, index) => Divider(color: textColor.withValues(alpha: 0.1)),
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
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    foregroundColor: accentColor,
                    child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  subtitle: Text('Enrolled', style: TextStyle(color: textColor.withValues(alpha: 0.6))),
                  trailing: widget.course.isOwner
                      ? Icon(Icons.message, size: 20, color: accentColor)
                      : null,
                  onTap: widget.course.isOwner
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PrivateChatScreen(
                                course: widget.course,
                                student: Student(
                                  id: '${widget.course.id}_private_chat',
                                  name: name,
                                  avatar: initial,
                                ),
                              ),
                            ),
                          );
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
