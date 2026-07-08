import 'package:flutter/material.dart';
import '../models/course.dart';
import 'chat_screen.dart';
import 'assignments_screen.dart';
import 'quizzes_exams_screen.dart';
import 'students_list_screen.dart';
import 'course_settings_screen.dart';
// AIQuestionnaireScreen import removed as it is now accessed via Assignments/Quizzes screens

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
  @override
  Widget build(BuildContext context) {
    final bool isTeacherView = widget.course.isOwner;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.code),
        backgroundColor: widget.course.gradient[0],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.forum),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatScreen(course: widget.course)),
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.course.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.course.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!isTeacherView)
                    Text(
                      'Instructor: ${widget.course.instructor}',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics Overview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  isTeacherView ? _buildTeacherAnalytics(context) : _buildStudentAnalytics(context),
                  const SizedBox(height: 24),
                  Text(
                    'Course Materials',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    context,
                    'Assignments',
                    isTeacherView ? 'View and create assignments' : '3 pending assignments',
                    Icons.assignment,
                    Colors.orange,
                    () => Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => AssignmentsScreen(isOwner: isTeacherView))
                    ),
                  ),
                  _buildSectionCard(
                    context,
                    'Quizzes & Exams',
                    isTeacherView ? 'Manage exams with AI' : 'Next exam on Friday',
                    Icons.quiz,
                    Colors.red,
                    () => Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => QuizzesExamsScreen(isOwner: isTeacherView))
                    ),
                  ),
                  _buildSectionCard(
                    context,
                    'Students',
                    '${widget.course.enrolledStudents.length} enrolled students',
                    Icons.people,
                    Colors.blue,
                    () => Navigator.push(context, MaterialPageRoute(builder: (context) => StudentsListScreen(course: widget.course))),
                  ),
                  if (isTeacherView)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add_a_photo),
                          label: const Text('SCAN NEW ANSWER SHEET'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherAnalytics(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Class Avg.',
                '78%',
                Icons.analytics,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Passing Rate',
                '92%',
                Icons.trending_up,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Score Distribution',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 16),
                _buildSimpleBarChart(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentAnalytics(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'My Grade',
                widget.course.averageGrade,
                Icons.person,
                Colors.deepPurple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Class Avg.',
                '78%',
                Icons.groups,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exam Progress',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: 0.65,
                    minHeight: 12,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(widget.course.gradient[0]),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '65% of course requirements completed',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(BuildContext context, String label, String value, IconData icon, Color color) {
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

  Widget _buildSimpleBarChart(BuildContext context) {
    final heights = [0.3, 0.5, 0.8, 0.6, 0.4];
    final labels = ['F', 'D', 'C', 'B', 'A'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (index) {
        return Column(
          children: [
            Container(
              width: 30,
              height: 100 * heights[index],
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(150),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[index], style: const TextStyle(fontSize: 10)),
          ],
        );
      }),
    );
  }

  Widget _buildSectionCard(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
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
