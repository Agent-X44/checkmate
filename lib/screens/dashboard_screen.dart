import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';
import 'course_dashboard_screen.dart';
import 'quizzes_exams_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _createdExpanded = true;
  bool _enrolledExpanded = true;

  List<Course> _myCourses = [];
  List<Course> _enrolledCourses = [];
  bool _isInitialLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  void addCreatedCourse(Course course) {
    if (mounted) {
      setState(() {
        _myCourses.insert(0, course);
      });
    }
  }

  void addEnrolledCourse(Course course) {
    if (mounted) {
      setState(() {
        _enrolledCourses.insert(0, course);
      });
    }
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
          _loadFailed = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard refresh error: $e");
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _loadFailed = true;
        });
      }
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
          CheckMateUi.showTopPrompt(context, 'Course deleted successfully',
              isError: false);
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
                  CheckMateUi.showTopPrompt(
                      context, 'Course renamed successfully!',
                      isError: false);
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
        CheckMateUi.showTopPrompt(context, 'Join code reset to: $newCode',
            isError: false);
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
          CheckMateUi.showTopPrompt(context, 'Left course successfully',
              isError: false);
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
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCombinedSummary(BuildContext context, int totalCourses) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final rawName = user?.userMetadata?['name']?.toString().trim();
    final firstName = rawName == null || rawName.isEmpty
        ? 'there'
        : rawName.split(' ').first;
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi, $firstName',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 3),
              Text(
                totalCourses == 0
                    ? 'Your learning space is ready.'
                    : '$totalCourses ${totalCourses == 1 ? 'course' : 'courses'} in your space',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 320 || compact;
                    final created = _buildSummaryStat(
                        context, Icons.edit_note_outlined, 'Created',
                        '${_myCourses.length}');
                    final enrolled = _buildSummaryStat(
                        context, Icons.school_outlined, 'Enrolled',
                        '${_enrolledCourses.length}');
                    if (stacked) {
                      return Column(
                        children: [
                          created,
                          const Divider(height: 24),
                          enrolled,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: created),
                        SizedBox(
                          height: 34,
                          child: VerticalDivider(
                            color: colors.outlineVariant,
                            width: 24,
                          ),
                        ),
                        Expanded(child: enrolled),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark
        ? colors.secondary
        : colors.primary;
    return Row(
      children: [
        Icon(icon, size: 23, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourseGrid(BuildContext context, List<Course> courses) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final columns =
                    !largeText && constraints.maxWidth >= 680 ? 2 : 1;
                final cardWidth =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final course in courses)
                      SizedBox(
                        width: cardWidth,
                        child: _buildCourseCard(context, course),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, Course course) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? colors.secondary : colors.primary;
    final gradient = course.adaptiveGradient(context);

    void openCourse() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CourseDashboardScreen(
            course: course,
            onCourseDeleted: () {},
          ),
        ),
      );
    }

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openCourse,
        onLongPress: course.isOwner ? () => _deleteCourse(course) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  course.isOwner ? Icons.menu_book_outlined : Icons.school_outlined,
                  color: dark ? const Color(0xFF141318) : Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        course.isOwner ? 'Teaching' : 'Enrolled',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.isOwner
                            ? 'Code ${course.code}'
                            : 'With ${course.instructor}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (!course.isOwner)
                        Text(
                          'Avg. grade ${course.averageGrade}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Course options',
                    icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _renameCourse(course);
                      } else if (value == 'reset_code') {
                        _resetCourseCode(course);
                      } else if (value == 'delete') {
                        _deleteCourse(course);
                      } else if (value == 'leave') {
                        _unenrollCourse(course);
                      }
                    },
                    itemBuilder: (context) => course.isOwner
                        ? const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename course'),
                            ),
                            PopupMenuItem(
                              value: 'reset_code',
                              child: Text('Reset join code'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete course'),
                            ),
                          ]
                        : const [
                            PopupMenuItem(
                              value: 'leave',
                              child: Text('Leave course'),
                            ),
                          ],
                  ),
                  if (course.isOwner)
                    IconButton(
                      tooltip: 'Open answer sheets',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuizzesExamsScreen(
                              courseId: course.id,
                              isOwner: course.isOwner,
                            ),
                          ),
                        );
                      },
                      icon: Icon(Icons.print_outlined, color: accent),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.chevron_right, color: accent),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading && _myCourses.isEmpty && _enrolledCourses.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _buildCombinedSummary(
                  context, _myCourses.length + _enrolledCourses.length),
            ),
            if (_myCourses.isNotEmpty) ...[
              _buildCollapsibleHeader(
                context,
                'Created Courses',
                _createdExpanded,
                () => setState(() => _createdExpanded = !_createdExpanded),
              ),
              if (_createdExpanded) _buildCourseGrid(context, _myCourses),
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
                _buildCourseGrid(context, _enrolledCourses),
            ],
            if (_myCourses.isEmpty && _enrolledCourses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _loadFailed
                                ? Icons.wifi_off_outlined
                                : Icons.school_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(
                            _loadFailed
                                ? 'Could not load courses'
                                : 'No courses yet',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                            _loadFailed
                                ? 'Check your connection and try again.'
                                : 'Create a course or join one to get started.',
                            textAlign: TextAlign.center),
                        if (_loadFailed) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _refreshAll,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (_myCourses.isNotEmpty || _enrolledCourses.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}
