import 'package:flutter/material.dart';
import '../models/course.dart';
import 'course_dashboard_screen.dart';
import 'answer_sheet_design_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _createdExpanded = true;
  bool _enrolledExpanded = true;

  void _deleteCourse(Course course) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text('Are you sure you want to delete ${course.code}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              setState(() {
                globalDummyCourses.removeWhere((c) => c.id == course.id);
              });
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myCourses = globalDummyCourses.where((c) => c.isOwner).toList();
    final enrolledCourses =
        globalDummyCourses.where((c) => !c.isOwner).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildCombinedSummary(context),
          ),

          // Created Courses Section
          if (myCourses.isNotEmpty) ...[
            _buildCollapsibleHeader(
              context,
              'Created Courses',
              _createdExpanded,
              () => setState(() => _createdExpanded = !_createdExpanded),
            ),
            if (_createdExpanded)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: _buildCourseGrid(context, myCourses),
              ),
          ],

          // Enrolled Courses Section
          if (enrolledCourses.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            _buildCollapsibleHeader(
              context,
              'Enrolled Courses',
              _enrolledExpanded,
              () => setState(() => _enrolledExpanded = !_enrolledExpanded),
            ),
            if (_enrolledExpanded)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: _buildCourseGrid(context, enrolledCourses),
              ),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: 100), // Space for FAB
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleHeader(
      BuildContext context, String title, bool isExpanded, VoidCallback onTap) {
    return SliverToBoxAdapter(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCombinedSummary(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      color:
          Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Academic Overview',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  context,
                  'Total Courses',
                  '${globalDummyCourses.length}',
                  Icons.auto_stories,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryCard(
                  context,
                  'Avg. Performance',
                  '88%',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseGrid(BuildContext context, List<Course> courses) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final course = courses[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildCourseCard(context, course),
          );
        },
        childCount: courses.length,
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, Course course) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onLongPress: course.isOwner ? () => _deleteCourse(course) : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CourseDashboardScreen(
                course: course,
                onCourseDeleted: () {
                  setState(() {
                    globalDummyCourses.removeWhere((c) => c.id == course.id);
                  });
                },
              ),
            ),
          );
        },
        child: Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: course.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.code,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_vert, color: Colors.white),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!course.isOwner)
                    Expanded(
                      child: Text(
                        course.instructor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                    )
                  else
                    const Spacer(),
                  if (!course.isOwner)
                    Text(
                      'Avg Grade: ${course.averageGrade}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (course.isOwner)
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const AnswerSheetDesignScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withAlpha(51),
                        child: const Icon(Icons.print,
                            size: 18, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
