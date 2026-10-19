import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/data_cache_service.dart';
import '../theme/checkmate_theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/motion.dart';
import 'dashboard_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'course_dashboard_screen.dart';
import 'notifications_screen.dart';
import '../main.dart'; // To access globalCameras

/// Main navigation shell for authenticated users.
/// Manages the BottomNavigationBar (Dashboard, Scanner, Settings) and Drawer (Course List).
/// Enforces BR-01: Course management entry points.
class MainNavigation extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onLogout;

  const MainNavigation({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onLogout,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final Stream<List<AppNotification>> _notificationStream =
      NotificationService.streamMine();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();

  StreamSubscription<CacheChange>? _cacheSubscription;
  List<Course> _drawerCachedCourses = [];
  bool _isDrawerLoading = true;
  late final StreamSubscription<Course> _joinedCourseSubscription;

  Future<void> _refreshDrawerCourses() async {
    final cached = await SupabaseService.cachedCourses();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _drawerCachedCourses = cached;
        _isDrawerLoading = false;
      });
    }
    try {
      await SupabaseService.refreshCourses();
      if (mounted) setState(() => _isDrawerLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isDrawerLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(NotificationService.startForCurrentUser());
    _cacheSubscription = DataCacheService.changes.listen((change) {
      if (!mounted ||
          change.kind != 'courses' ||
          change.userId != SupabaseService.currentUser?.id) {
        return;
      }
      setState(() {
        _drawerCachedCourses = (change.value as List)
            .map((row) => Course.fromMap(Map<String, dynamic>.from(row),
                isOwner: row['_is_owner'] == true))
            .toList();
        _isDrawerLoading = false;
      });
    });
    _refreshDrawerCourses();
    _joinedCourseSubscription = DeepLinkService.joinedCourses.listen((course) {
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
          _drawerCachedCourses
              .removeWhere((existing) => existing.id == course.id);
          _drawerCachedCourses.removeWhere((c) => c.id == course.id);
          _drawerCachedCourses.insert(0, course);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dashboardKey.currentState?.addEnrolledCourse(course);
        });
      }

      unawaited(_refreshDrawerCourses());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.startForCurrentUser());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _joinedCourseSubscription.cancel();
    _cacheSubscription?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  void _showCourseActions() {
    final theme = Theme.of(context);
    final accentColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text('Add a course', style: theme.textTheme.titleLarge),
              ),
              for (final (i, (icon, title, subtitle, action)) in [
                (
                  Icons.add_circle_outline,
                  'Create a course',
                  'Set up a class for your students',
                  _showCreateDialog
                ),
                (
                  Icons.group_add_outlined,
                  'Join a course',
                  'Enter course code or invitation link',
                  _showJoinDialog
                ),
              ].indexed)
                Reveal(
                  index: i,
                  offset: 12,
                  child: Pressable(
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: accentColor),
                      ),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        action();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Course name',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) {
                return;
              }
              final nav = Navigator.of(dialogContext);
              try {
                final newCourse = await SupabaseService.createClass(
                  name: nameCtrl.text,
                );
                nav.pop();
                if (!mounted) {
                  return;
                }
                setState(() {
                  _drawerCachedCourses.removeWhere((c) => c.id == newCourse.id);
                  _drawerCachedCourses.insert(0, newCourse);
                });
                _dashboardKey.currentState?.addCreatedCourse(newCourse);

                CheckMateUi.showTopPrompt(
                    context, 'Course created successfully!',
                    isError: false);
              } catch (e) {
                if (!mounted) {
                  return;
                }
                CheckMateUi.showTopPrompt(
                    context, 'Failed to create course: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: buttonTextColor,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    final joinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join a Course'),
        content: TextField(
          controller: joinCtrl,
          maxLength: 512,
          textCapitalization: TextCapitalization.none,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Course code or invite link',
            prefixIcon: Icon(Icons.link),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () async {
              var input = joinCtrl.text.trim();
              if (input.isEmpty) {
                return;
              }
              final inviteUri = Uri.tryParse(input);
              if (inviteUri != null &&
                  inviteUri.queryParameters.containsKey('inviteToken')) {
                input = inviteUri.queryParameters['inviteToken'] ?? '';
              } else if (inviteUri != null &&
                  (inviteUri.queryParameters.containsKey('joinCode') ||
                      inviteUri.queryParameters.containsKey('code'))) {
                CheckMateUi.showTopPrompt(
                  context,
                  'This old invitation link is no longer valid. Ask the instructor to share a new link.',
                );
                return;
              }
              final nav = Navigator.of(dialogContext);
              try {
                final course = DeepLinkService.isInviteToken(input)
                    ? await SupabaseService.joinCourseWithInvitation(input)
                    : await SupabaseService.joinClass(input);
                nav.pop();
                if (!mounted) {
                  return;
                }
                setState(() {
                  _drawerCachedCourses.removeWhere((c) => c.id == course.id);
                  _drawerCachedCourses.insert(0, course);
                });
                _dashboardKey.currentState?.addEnrolledCourse(course);

                CheckMateUi.showTopPrompt(
                    context, 'Joined course: ${course.name}!',
                    isError: false);
              } catch (e) {
                if (!mounted) {
                  return;
                }
                final msg = e.toString().replaceAll('Exception: ', '');
                CheckMateUi.showTopPrompt(context, msg,
                    isError: !msg.contains('already enrolled'));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: buttonTextColor,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/checkmate.png',
              width: 28,
              height: 28,
              color: isDark ? accentColor : Colors.white,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('CheckMate',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open courses',
            icon: const Icon(Icons.menu),
            onPressed: () {
              _refreshDrawerCourses();
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: _notificationStream,
            builder: (context, snapshot) {
              final unread =
                  snapshot.data?.where((n) => n.isUnread).length ?? 0;
              return IconButton(
                tooltip: unread == 0
                    ? 'Notifications'
                    : '$unread unread notifications',
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: AnimatedSwitcher(
                    duration: CheckMateTheme.fast,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(unread > 99 ? '99+' : '$unread',
                        key: ValueKey(unread)),
                  ),
                  child: Icon(unread > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_outlined),
                ),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const NotificationsScreen())),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Settings and profile',
              onPressed: () => _onItemTapped(2),
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: (isDark ? accentColor : Colors.white)
                    .withValues(alpha: 0.16),
                child: Icon(Icons.person,
                    color: isDark ? accentColor : Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Builder(
              builder: (context) {
                final user = Supabase.instance.client.auth.currentUser;
                final name = user?.userMetadata?['name'] ?? 'User';
                final email = user?.email ?? 'Academic Profile';
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final colorScheme = Theme.of(context).colorScheme;
                final contentColor =
                    isDark ? colorScheme.secondary : Colors.white;
                final avatarBg = contentColor.withValues(alpha: 0.14);

                final initial = name.toString().trim();
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      20, MediaQuery.paddingOf(context).top + 24, 20, 22),
                  decoration: BoxDecoration(
                    gradient: isDark ? null : CheckMateTheme.brandGradient,
                    color: isDark ? colorScheme.surfaceContainerHigh : null,
                    borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: avatarBg,
                        child: Text(
                          initial.isEmpty ? '?' : initial[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: contentColor),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(name.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: contentColor)),
                      const SizedBox(height: 2),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: contentColor.withValues(alpha: 0.8))),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('YOUR COURSES',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_isDrawerLoading && _drawerCachedCourses.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_drawerCachedCourses.isEmpty) {
                    return const Center(
                      child: Text("No courses",
                          style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _drawerCachedCourses.length,
                    itemBuilder: (context, index) {
                      final course = _drawerCachedCourses[index];
                      return Reveal(
                        index: index,
                        offset: 10,
                        child: ListTile(
                          leading: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: course.adaptiveGradient(context)),
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          title: Text(course.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CourseDashboardScreen(
                                  course: course,
                                  onCourseDeleted: _refreshDrawerCourses,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ListTile(
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text('Log out',
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: widget.onLogout,
                ),
              ),
            ),
          ],
        ),
      ),
      body: TweenAnimationBuilder<double>(
        key: ValueKey(_selectedIndex),
        tween: Tween(begin: 0, end: 1),
        duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
            ? Duration.zero
            : CheckMateTheme.medium,
        curve: CheckMateTheme.emphasized,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)), child: child),
        ),
        child: Builder(
          builder: (context) {
            switch (_selectedIndex) {
              case 0:
                return DashboardScreen(key: _dashboardKey);
              case 1:
                return ScannerScreen(
                  key: const ValueKey('scanner-tab'),
                  cameras: globalCameras,
                  isActive: true,
                  onClose: () => _onItemTapped(0),
                );
              case 2:
                return SettingsScreen(
                  themeMode: widget.themeMode,
                  onThemeChanged: widget.onThemeChanged,
                  onLogout: widget.onLogout,
                  onProfileUpdated: () => setState(() {}),
                );
              default:
                return DashboardScreen(key: _dashboardKey);
            }
          },
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
              top:
                  BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard, color: accentColor),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner, color: accentColor),
                  label: 'Scan',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings, color: accentColor),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _showCourseActions,
              tooltip: 'Create or join a course',
              backgroundColor: accentColor,
              foregroundColor: isDark ? Colors.black : Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Course'),
            )
          : null,
    );
  }
}
