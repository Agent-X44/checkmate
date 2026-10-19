import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../services/data_cache_service.dart';
import '../theme/checkmate_theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/motion.dart';
import 'course_dashboard_screen.dart';
import 'quizzes_exams_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<CacheChange>? _cacheSubscription;
  void _applyCourses(List<Course> courses) {
    if (!mounted) {
      return;
    }
    setState(() {
      _myCourses = courses.where((c) => c.isOwner).toList();
      _enrolledCourses = courses.where((c) => !c.isOwner).toList();
      _isInitialLoading = false;
    });
  }

  @override
  void dispose() {
    _cacheSubscription?.cancel();
    super.dispose();
  }

  bool _createdExpanded = true;
  bool _enrolledExpanded = true;

  List<Course> _myCourses = [];
  List<Course> _enrolledCourses = [];
  final Map<String, Course> _confirmedJoinedCourses = {};
  bool _isInitialLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _cacheSubscription = DataCacheService.changes.listen((change) {
      if (change.kind == 'courses' &&
          change.userId == SupabaseService.currentUser?.id) {
        _applyCourses((change.value as List)
            .map((row) => Course.fromMap(Map<String, dynamic>.from(row),
                isOwner: row['_is_owner'] == true))
            .toList());
      }
    });
    _loadCachedCourses();
  }

  void addCreatedCourse(Course course) {
    if (mounted) {
      setState(() {
        _myCourses.removeWhere((existing) => existing.id == course.id);
        _myCourses.insert(0, course);
      });
    }
  }

  void addEnrolledCourse(Course course) {
    _confirmedJoinedCourses[course.id] = course;
    if (mounted) {
      setState(() {
        _enrolledCourses.removeWhere((existing) => existing.id == course.id);
        _enrolledCourses.insert(0, course);
      });
    }
  }

  Future<void> refreshCourses() => _refreshAll();

  Future<void> _loadCachedCourses() async {
    final cached = await SupabaseService.cachedCourses();
    if (cached.isNotEmpty) _applyCourses(cached);
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    try {
      await SupabaseService.refreshCourses();
      if (mounted) setState(() => _loadFailed = false);
    } catch (e) {
      debugPrint('Dashboard refresh error: $e');
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                return;
              }
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
            child: const Text('Save'),
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.unenrollClass(course.id);
        if (mounted) {
          _confirmedJoinedCourses.remove(course.id);
          setState(() {
            _enrolledCourses
                .removeWhere((enrolled) => enrolled.id == course.id);
          });
          CheckMateUi.showTopPrompt(context, 'Left course successfully',
              isError: false);
          await _refreshAll();
        }
      } catch (e) {
        if (mounted) {
          CheckMateUi.showTopPrompt(context, 'Leave failed: $e');
        }
      }
    }
  }

  Widget _buildCollapsibleHeader(BuildContext context, String title, int count,
      bool isExpanded, VoidCallback onTap) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent =
        theme.brightness == Brightness.dark ? colors.secondary : colors.primary;
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text(title, style: theme.textTheme.titleLarge),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('$count',
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: accent, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0 : -0.25,
                      duration: CheckMateTheme.medium,
                      curve: CheckMateTheme.emphasized,
                      child: Icon(Icons.keyboard_arrow_down,
                          color: colors.onSurfaceVariant),
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
    final dark = theme.brightness == Brightness.dark;
    final onHero = dark ? colors.secondary : Colors.white;
    final user = Supabase.instance.client.auth.currentUser;
    final rawName = user?.userMetadata?['name']?.toString().trim();
    final firstName =
        rawName == null || rawName.isEmpty ? 'there' : rawName.split(' ').first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Reveal(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: dark ? null : CheckMateTheme.brandGradient,
                color: dark ? colors.surfaceContainerHigh : null,
                borderRadius: BorderRadius.circular(28),
                boxShadow: dark
                    ? null
                    : [
                        BoxShadow(
                          color: CheckMateTheme.blue.withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -28,
                    top: -18,
                    child: ExcludeSemantics(
                      child: Image.asset(
                        'assets/checkmate.png',
                        width: 150,
                        height: 150,
                        color: onHero.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: onHero.withValues(alpha: 0.75),
                                letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text('Hi, $firstName',
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: onHero)),
                        const SizedBox(height: 4),
                        Text(
                          totalCourses == 0
                              ? 'Your learning space is ready.'
                              : '$totalCourses ${totalCourses == 1 ? 'course' : 'courses'} in your space',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: onHero.withValues(alpha: 0.8)),
                        ),
                        const SizedBox(height: 18),
                        Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          children: [
                            _wrapStat(
                                compact,
                                _buildSummaryStat(context, Icons.edit_note,
                                    'Teaching', _myCourses.length, onHero)),
                            SizedBox(width: 10, height: compact ? 10 : 0),
                            _wrapStat(
                                compact,
                                _buildSummaryStat(
                                    context,
                                    Icons.school,
                                    'Enrolled',
                                    _enrolledCourses.length,
                                    onHero)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapStat(bool compact, Widget child) =>
      compact ? child : Expanded(child: child);

  Widget _buildSummaryStat(BuildContext context, IconData icon, String label,
      int value, Color onHero) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: onHero.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: onHero),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: CheckMateTheme.slow * 2,
                  curve: CheckMateTheme.emphasized,
                  builder: (context, v, _) => Text('${v.round()}',
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: onHero, fontWeight: FontWeight.w800)),
                ),
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: onHero.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, List<Course> courses, bool expanded) {
    return SliverToBoxAdapter(
      child: AnimatedSize(
        duration: CheckMateTheme.medium,
        curve: CheckMateTheme.emphasized,
        alignment: Alignment.topCenter,
        child: expanded
            ? _buildCourseGrid(context, courses)
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  Widget _buildCourseGrid(BuildContext context, List<Course> courses) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final columns = !largeText && constraints.maxWidth >= 680 ? 2 : 1;
              final cardWidth =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (i, course) in courses.indexed)
                    SizedBox(
                      width: cardWidth,
                      child: Reveal(
                        key: ValueKey(course.id),
                        index: i + 1,
                        child:
                            Pressable(child: _buildCourseCard(context, course)),
                      ),
                    ),
                ],
              );
            },
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openCourse,
        onLongPress: course.isOwner ? () => _deleteCourse(course) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  course.isOwner
                      ? Icons.menu_book_outlined
                      : Icons.school_outlined,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          course.isOwner ? 'Teaching' : 'Enrolled',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
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

  Color _accent(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
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
                'Teaching',
                _myCourses.length,
                _createdExpanded,
                () => setState(() => _createdExpanded = !_createdExpanded),
              ),
              _buildSection(context, _myCourses, _createdExpanded),
            ],
            if (_enrolledCourses.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              _buildCollapsibleHeader(
                context,
                'Enrolled',
                _enrolledCourses.length,
                _enrolledExpanded,
                () => setState(() => _enrolledExpanded = !_enrolledExpanded),
              ),
              _buildSection(context, _enrolledCourses, _enrolledExpanded),
            ],
            if (_myCourses.isEmpty && _enrolledCourses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Reveal(
                      index: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: _accent(context).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                                _loadFailed
                                    ? Icons.wifi_off_outlined
                                    : Icons.school_outlined,
                                size: 40,
                                color: _accent(context)),
                          ),
                          const SizedBox(height: 16),
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
              ),
            if (_myCourses.isNotEmpty || _enrolledCourses.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}
