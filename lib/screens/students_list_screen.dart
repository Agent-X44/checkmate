import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../services/data_cache_service.dart';
import 'private_chat_screen.dart';

class StudentsListScreen extends StatefulWidget {
  final Course course;
  const StudentsListScreen({super.key, required this.course});

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  List<Map<String, dynamic>>? _students;

  @override
  void initState() {
    super.initState();
    _initStudentsWithCache();
  }

  Future<void> _initStudentsWithCache() async {
    // 1. Instant cache load for seamless UX
    final cached = await DataCacheService.getEnrolledStudents(widget.course.id);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _students = cached;
      });
    }

    // 2. Fetch fresh network data and update cache
    _loadStudents();
  }

  void _loadStudents() {
    final future = SupabaseService.getEnrolledStudents(widget.course.id);
    setState(() => _studentsFuture = future);
    future.then((fresh) {
      if (fresh.isNotEmpty) {
        DataCacheService.saveEnrolledStudents(widget.course.id, fresh);
      }
      if (mounted) {
        setState(() => _students = fresh);
      }
    }).catchError((e) {
      debugPrint("Error fetching enrolled students: $e");
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent =
        theme.brightness == Brightness.dark ? colors.secondary : colors.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _studentsFuture,
        builder: (context, snapshot) {
          final students = snapshot.data ?? _students;
          if (students == null &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && students == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_outlined, size: 48, color: accent),
                    const SizedBox(height: 12),
                    Text('Could not load students',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('Check your connection and try again.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => setState(_loadStudents),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final studentList = students ?? [];
          if (studentList.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline, size: 48, color: accent),
                    const SizedBox(height: 12),
                    Text('No students enrolled yet',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text(
                        'Students who join this course will appear here.',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                itemCount: studentList.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '${studentList.length} ${studentList.length == 1 ? 'student' : 'students'}',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  final rawProfile = studentList[index - 1]['profiles'];
                  final String name = rawProfile is Map
                      ? rawProfile['name']?.toString() ?? 'Student'
                      : 'Student';
                  final initial = name.trim().isNotEmpty
                      ? name.trim()[0].toUpperCase()
                      : '?';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.12),
                        foregroundColor: accent,
                        child: Text(initial,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Enrolled student'),
                      trailing: widget.course.isOwner
                          ? Icon(Icons.message_outlined, color: accent)
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
              ),
            ),
          );
        },
      ),
    );
  }
}
