import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../services/data_cache_service.dart';
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
    // 1. Instant cache retrieval for seamless UX
    final cached = await DataCacheService.getClassAnalytics(widget.course.id);
    if (cached != null && mounted) {
      setState(() {
        _analytics = cached;
        _loadingAnalytics = false;
      });
    }

    // 2. Fetch fresh network analytics and update cache
    try {
      final data = await SupabaseService.getClassAnalytics(widget.course.id);
      await DataCacheService.saveClassAnalytics(widget.course.id, data);
      if (mounted) {
        setState(() {
          _analytics = data;
          _loadingAnalytics = false;
        });
      }
    } catch (_) {
      if (mounted && _analytics == null) {
        setState(() => _loadingAnalytics = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacherView = widget.course.isOwner;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? colors.secondary : colors.primary;
    final gradient = widget.course.adaptiveGradient(context);
    final darkInk = dark ||
        gradient.any((color) => color.computeLuminance() > 0.35);
    final headerInk = darkInk ? const Color(0xFF141318) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Course chat',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(course: widget.course),
              ),
            ),
          ),
          if (isTeacherView)
            IconButton(
              tooltip: 'Course settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CourseSettingsScreen(
                    course: widget.course,
                    onDelete: () => widget.onCourseDeleted?.call(),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.menu_book_outlined,
                                color: headerInk, size: 25),
                            const SizedBox(height: 11),
                            Text(
                              widget.course.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: headerInk,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              isTeacherView
                                  ? 'Teaching · Code ${widget.course.joinCode}'
                                  : 'With ${widget.course.instructor}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: headerInk.withValues(alpha: 0.86),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Class snapshot',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      _loadingAnalytics
                          ? const LinearProgressIndicator()
                          : isTeacherView
                              ? _buildTeacherAnalytics(context)
                              : _buildStudentAnalytics(context),
                      const SizedBox(height: 24),
                      Text('Explore course',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Material(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _buildActionRow(
                              context,
                              'Learning materials',
                              isTeacherView
                                  ? 'Upload or view course files'
                                  : 'Browse course files',
                              Icons.folder_open_outlined,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LearningMaterialsScreen(
                                    isOwner: isTeacherView,
                                    courseId: widget.course.id,
                                  ),
                                ),
                              ),
                            ),
                            Divider(height: 1, indent: 66,
                                color: colors.outlineVariant),
                            _buildActionRow(
                              context,
                              'Quizzes & exams',
                              isTeacherView
                                  ? 'Manage assessments'
                                  : 'View your results',
                              Icons.quiz_outlined,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => QuizzesExamsScreen(
                                    isOwner: isTeacherView,
                                    courseId: widget.course.id,
                                  ),
                                ),
                              ),
                            ),
                            Divider(height: 1, indent: 66,
                                color: colors.outlineVariant),
                            _buildActionRow(
                              context,
                              'Students',
                              isTeacherView
                                  ? 'View enrolled students'
                                  : 'Connect with classmates',
                              Icons.people_outline,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      StudentsListScreen(course: widget.course),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTeacherView) ...[
                        const SizedBox(height: 22),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: dark
                                    ? colors.onSecondary
                                    : colors.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ScannerScreen(
                                    cameras: globalCameras,
                                    isActive: true,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Scan new answer sheet'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherAnalytics(BuildContext context) {
    final avg = _analytics?['avg']?.toStringAsFixed(1) ?? '0.0';
    return _buildMetricPair(
      context,
      firstLabel: 'Class average',
      firstValue: '$avg%',
      firstIcon: Icons.analytics_outlined,
      secondLabel: 'Participation',
      secondValue: '${_analytics?['count'] ?? 0}',
      secondIcon: Icons.groups_outlined,
    );
  }

  Widget _buildStudentAnalytics(BuildContext context) {
    final avg = _analytics?['avg']?.toStringAsFixed(1) ?? '0.0';
    return _buildMetricPair(
      context,
      firstLabel: 'Class average',
      firstValue: '$avg%',
      firstIcon: Icons.analytics_outlined,
      secondLabel: 'Requirements',
      secondValue: 'Completed',
      secondIcon: Icons.check_circle_outline,
    );
  }

  Widget _buildMetricPair(
    BuildContext context, {
    required String firstLabel,
    required String firstValue,
    required IconData firstIcon,
    required String secondLabel,
    required String secondValue,
    required IconData secondIcon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final first = _buildMetricItem(
              context, firstLabel, firstValue, firstIcon);
          final second = _buildMetricItem(
              context, secondLabel, secondValue, secondIcon);
          if (stacked) {
            return Column(
              children: [
                first,
                const Divider(height: 24),
                second,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: first),
              SizedBox(
                height: 36,
                child: VerticalDivider(
                  color: colors.outlineVariant,
                  width: 22,
                ),
              ),
              Expanded(child: second),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricItem(
      BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark
        ? colors.secondary
        : colors.primary;
    return Row(
      children: [
        Icon(icon, size: 23, color: accent),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark
        ? colors.secondary
        : colors.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: accent.withValues(alpha: 0.12),
        child: Icon(icon, size: 20, color: accent),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
