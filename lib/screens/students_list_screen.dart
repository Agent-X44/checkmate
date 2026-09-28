import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../services/data_cache_service.dart';
import 'private_chat_screen.dart';
import 'student_overall_analysis_screen.dart';

class StudentsListScreen extends StatefulWidget {
  final Course course;
  const StudentsListScreen({super.key, required this.course});

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  List<Map<String, dynamic>>? _students;
  final Set<String> _removingStudentIds = {};
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _studentsFuture = _fetchStudents();
    _initStudentsWithCache();
  }

  Future<void> _initStudentsWithCache() async {
    // 1. Instant cache load for seamless UX
    final cached = await DataCacheService.getEnrolledStudents(widget.course.id);
    if (cached.isNotEmpty && mounted && _students == null) {
      setState(() {
        _students = cached;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchStudents() async {
    final requestGeneration = ++_requestGeneration;
    final fresh = await SupabaseService.getEnrolledStudents(widget.course.id);
    if (requestGeneration == _requestGeneration) {
      await DataCacheService.saveEnrolledStudents(widget.course.id, fresh);
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() => _students = fresh);
      }
    }
    return fresh;
  }

  void _loadStudents() {
    setState(() => _studentsFuture = _fetchStudents());
  }

  Future<void> _unenrollStudent(String studentId, String name) async {
    if (!widget.course.isOwner || _removingStudentIds.contains(studentId)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unenroll $name?'),
        content: const Text(
          'The student will lose access to this course. Existing grades and results will remain saved. They can rejoin with the course code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Unenroll'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _requestGeneration++; // Ignore a student-list request started before removal.
    setState(() => _removingStudentIds.add(studentId));
    try {
      await SupabaseService.unenrollStudent(widget.course.id, studentId);
      if (!mounted) return;
      final remaining = (_students ?? <Map<String, dynamic>>[])
          .where((student) => student['user_id']?.toString() != studentId)
          .toList();
      setState(() => _students = remaining);
      await DataCacheService.saveEnrolledStudents(widget.course.id, remaining);
      if (!mounted) return;
      _loadStudents();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name was unenrolled.')),
      );
    } catch (e) {
      if (mounted) {
        _loadStudents();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unenroll $name: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _removingStudentIds.remove(studentId));
    }
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
          final students = _students ?? snapshot.data;
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
                  final studentId =
                      studentList[index - 1]['user_id']?.toString();
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
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.message_outlined, color: accent),
                                PopupMenuButton<String>(
                                  tooltip: 'Manage $name',
                                  enabled: studentId != null &&
                                      !_removingStudentIds.contains(studentId),
                                  icon: _removingStudentIds.contains(studentId)
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(Icons.more_vert, color: accent),
                                  onSelected: (action) {
                                    if (action == 'unenroll' &&
                                        studentId != null) {
                                      _unenrollStudent(studentId, name);
                                    } else if (action == 'analysis' &&
                                        studentId != null) {
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                StudentOverallAnalysisScreen(
                                              studentId: studentId,
                                              classId: widget.course.id,
                                              studentName: name,
                                            ),
                                          ));
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'analysis',
                                      child: Text('Performance analysis'),
                                    ),
                                    PopupMenuItem(
                                      value: 'unenroll',
                                      child: Text(
                                        'Unenroll student',
                                        style: TextStyle(color: colors.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
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
