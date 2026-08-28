import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';
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
  
  List<Course> _myCourses = [];
  List<Course> _enrolledCourses = [];
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    try {
      final my = await SupabaseService.getCreatedCoursesDetails();
      final enrolled = await SupabaseService.getEnrolledCoursesDetails();
      if (mounted) {
        setState(() {
          _myCourses = my;
          _enrolledCourses = enrolled;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard refresh error: $e");
    }
  }

  void _deleteCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text('Are you sure you want to delete ${course.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.deleteClass(course.id);
        if (mounted) {
          CheckMateUi.showTopPrompt(context, 'Course deleted successfully', isError: false);
          _refreshAll();
        }
      } catch (e) {
        if (mounted) {
          CheckMateUi.showTopPrompt(context, 'Delete failed: $e');
        }
      }
    }
  }

  void _renameCourse(Course course) {
    final controller = TextEditingController(text: course.name);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Course Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(dialogContext);
              try {
                await SupabaseService.renameClass(course.id, newName);
                if (mounted) {
                  CheckMateUi.showTopPrompt(context, 'Course renamed successfully!', isError: false);
                  _refreshAll();
                }
              } catch (e) {
                if (mounted) {
                  CheckMateUi.showTopPrompt(context, 'Rename failed: $e');
                }
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _resetCourseCode(Course course) async {
    try {
      final newCode = await SupabaseService.resetCourseCode(course.id);
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Join code reset to: $newCode', isError: false);
        _refreshAll();
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Reset code failed: $e');
      }
    }
  }

  void _unenrollCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Course'),
        content: Text('Are you sure you want to leave ${course.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('LEAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.unenrollClass(course.id);
        if (mounted) {
          CheckMateUi.showTopPrompt(context, 'Left course successfully', isError: false);
          _refreshAll();
        }
      } catch (e) {
        if (mounted) {
          CheckMateUi.showTopPrompt(context, 'Leave failed: $e');
        }
      }
    }
  }

  Widget _buildCollapsibleHeader(
      BuildContext context, String title, bool isExpanded, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      color: isDark ? Colors.white : Colors.black,
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

  Widget _buildCombinedSummary(BuildContext context, int totalCourses) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final firstName = (user?.userMetadata?['name']?.toString().split(' ').first) ?? 'Student';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      color:
          Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hi, $firstName 👋',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black),
          ),
          const SizedBox(height: 4),
          Text(
            'Academic Overview',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  context,
                  'Total Courses',
                  '$totalCourses',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = course.adaptiveGradient(context);
    // Dark Mode -> Dark text & icons matching scaffold background (#141318) for high contrast on soft pastel cards
    // Light Mode -> Crisp White text & icons for contrast on vibrant saturated cards
    final contentColor = isDark ? const Color(0xFF141318) : Colors.white;
    final iconBgColor = isDark
        ? Colors.black.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.25);

    if (course.isOwner) {
      // Created Courses: Course name is centered vertically in the card
      return Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: InkWell(
          onLongPress: () => _deleteCourse(course),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CourseDashboardScreen(
                  course: course,
                  onCourseDeleted: () {},
                ),
              ),
            );
          },
          child: Container(
            height: 108,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Vertically Centered Course Name
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 52.0, top: 12.0, bottom: 12.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: contentColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Right Options Icon with PopupMenu
                Positioned(
                  top: 4,
                  right: 4,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: contentColor),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _renameCourse(course);
                      } else if (value == 'reset_code') {
                        _resetCourseCode(course);
                      } else if (value == 'delete') {
                        _deleteCourse(course);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Rename Course'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'reset_code',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 8),
                            Text('Reset Join Code'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete Course', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Right Print Action Button
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AnswerSheetDesignScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: iconBgColor,
                      child: Icon(Icons.print, size: 16, color: contentColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Enrolled Courses: Top course title + bottom instructor line
      return Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CourseDashboardScreen(
                  course: course,
                  onCourseDeleted: () {},
                ),
              ),
            );
          },
          child: Container(
            height: 138,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
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
                      child: Text(
                        course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: contentColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: contentColor),
                      onSelected: (value) {
                        if (value == 'leave') {
                          _unenrollCourse(course);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'leave',
                          child: Row(
                            children: [
                              Icon(Icons.exit_to_app, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('Leave Course', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Instructor: ${course.instructor}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: contentColor.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      'Avg Grade: ${course.averageGrade}',
                      style: TextStyle(
                        color: contentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder(
        stream: SupabaseService.streamCreatedCourses(),
        builder: (context, snapshotCreated) {
          return StreamBuilder(
            stream: SupabaseService.streamEnrolledCourses(),
            builder: (context, snapshotEnrolled) {
              
              // Trigger detailed refresh in next frame to avoid setState-during-build error
              if (snapshotCreated.hasData || snapshotEnrolled.hasData) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _refreshAll();
                });
              }

              if (_isInitialLoading && _myCourses.isEmpty && _enrolledCourses.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return RefreshIndicator(
                onRefresh: _refreshAll,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildCombinedSummary(context, _myCourses.length + _enrolledCourses.length),
                    ),

                    if (_myCourses.isNotEmpty) ...[
                      _buildCollapsibleHeader(
                        context,
                        'Created Courses',
                        _createdExpanded,
                        () => setState(() => _createdExpanded = !_createdExpanded),
                      ),
                      if (_createdExpanded)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          sliver: _buildCourseGrid(context, _myCourses),
                        ),
                    ],

                    if (_enrolledCourses.isNotEmpty) ...[
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
                          sliver: _buildCourseGrid(context, _enrolledCourses),
                        ),
                    ],

                    if (_myCourses.isEmpty && _enrolledCourses.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text("No courses yet. Create or Join one!", 
                            style: TextStyle(color: Colors.grey)),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
