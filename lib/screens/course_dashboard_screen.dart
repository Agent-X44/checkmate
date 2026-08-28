import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import 'chat_screen.dart';
import 'learning_materials_screen.dart';
import 'quizzes_exams_screen.dart';
import 'students_list_screen.dart';
import 'course_settings_screen.dart';
import 'scanner_screen.dart';
import '../main.dart';

/// Central hub for a specific course. 
/// Provides access to quizzes/exams, enrolled students, and course-specific settings.
class CourseDashboardScreen extends StatefulWidget {
  final Course course;
  final VoidCallback? onCourseDeleted;

  const CourseDashboardScreen({
    super.key,
    required this.course,
    this.onCourseDeleted,
  });

  @override
  State<CourseDashboardScreen> createState() => _CourseDashboardScreenState();
}

class _CourseDashboardScreenState extends State<CourseDashboardScreen> {
  Map<String, dynamic>? _analytics;
  bool _loadingAnalytics = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      final data = await SupabaseService.getClassAnalytics(widget.course.id);
      if (mounted) {
        setState(() {
          _analytics = data;
          _loadingAnalytics = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAnalytics = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTeacherView = widget.course.isOwner;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = widget.course.adaptiveGradient(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.course.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (!isTeacherView)
              Text(
                'Instructor: ${widget.course.instructor}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: gradient[0],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.forum),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => ChatScreen(course: widget.course)),
              );
            },
          ),
          if (isTeacherView)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CourseSettingsScreen(
                      course: widget.course,
                      onDelete: () {
                        if (widget.onCourseDeleted != null) {
                          widget.onCourseDeleted!();
                        }
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analytics Overview',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _loadingAnalytics 
                      ? const LinearProgressIndicator()
                      : isTeacherView
                          ? _buildTeacherAnalytics(context)
                          : _buildStudentAnalytics(context),
                    const SizedBox(height: 24),
                    Text(
                      'Course Materials',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      context,
                      'Learning Materials',
                      isTeacherView
                          ? 'Upload PPTX, DOCX, and PDF'
                          : 'View course materials',
                      Icons.folder_shared,
                      Colors.blue,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  LearningMaterialsScreen(
                                    isOwner: isTeacherView,
                                    courseId: widget.course.id,
                                  ))),
                    ),
                    _buildSectionCard(
                      context,
                      'Quizzes & Exams',
                      isTeacherView
                          ? 'Manage exams with AI'
                          : 'View your results',
                      Icons.quiz,
                      Colors.red,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  QuizzesExamsScreen(
                                    isOwner: isTeacherView,
                                    courseId: widget.course.id,
                                  ))),
                    ),
                    _buildSectionCard(
                      context,
                      'Students',
                      isTeacherView 
                        ? 'View enrolled students'
                        : 'Connect with classmates',
                      Icons.people,
                      Colors.blue,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  StudentsListScreen(course: widget.course))),
                    ),
                    if (isTeacherView)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () {
                                Navigator.push(
                                  context,
                                  // isActive set to true because this is a direct action to start scanning.
                                  MaterialPageRoute(builder: (context) => ScannerScreen(cameras: globalCameras, isActive: true)),
                                );
                            },
                            icon: const Icon(Icons.add_a_photo),
                            label: const Text('SCAN NEW ANSWER SHEET'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gradient[0],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherAnalytics(BuildContext context) {
    final avg = _analytics?['avg']?.toStringAsFixed(1) ?? '0.0';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Class Avg.',
                '$avg%',
                Icons.analytics,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Participation',
                '${_analytics?['count'] ?? 0}',
                Icons.groups,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStudentAnalytics(BuildContext context) {
    final avg = _analytics?['avg']?.toStringAsFixed(1) ?? '0.0';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Class Avg.',
                '$avg%',
                Icons.groups,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Requirements',
                'Completed',
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(BuildContext context, String label, String value,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, String title, String subtitle,
      IconData icon, Color color, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(26),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
