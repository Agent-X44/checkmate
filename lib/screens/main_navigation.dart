import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';
import 'dashboard_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'course_dashboard_screen.dart';
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

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  bool _notificationsOn = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();

  List<Course> _drawerCachedCourses = [];
  bool _isDrawerLoading = true;

  Future<void> _refreshDrawerCourses() async {
    try {
      final results = await Future.wait([
        SupabaseService.getCreatedCoursesDetails(),
        SupabaseService.getEnrolledCoursesDetails(),
      ]);
      final all = [...results[0], ...results[1]];
      if (mounted) {
        setState(() {
          _drawerCachedCourses = all;
          _isDrawerLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isDrawerLoading = false);
      }
    }
  }

  Future<void> _loadNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsOn = prefs.getBool('notificationsEnabled') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _toggleNotifications() async {
    final newState = !_notificationsOn;

    if (newState) {
      debugPrint("DEBUG: Requesting Notification Permission...");
      var status = await Permission.notification.status;
      await Future.delayed(const Duration(milliseconds: 200));
      status = await Permission.notification.request();

      if (status.isPermanentlyDenied || status.isDenied) {
        if (mounted) _showPermissionSettingsDialog();
        return;
      }
    }

    setState(() {
      _notificationsOn = newState;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notificationsEnabled', newState);

      if (mounted) {
        CheckMateUi.showTopPrompt(
          context,
          newState ? 'Notifications Enabled' : 'Notifications Muted',
          isError: false,
        );
      }
    } catch (_) {}
  }

  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Permission'),
        content: const Text(
            'Notifications are currently disabled. Please enable them in settings to receive updates.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
    _refreshDrawerCourses();
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
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: accentColor),
                title: const Text('Create a course'),
                subtitle: const Text('Set up a class for your students'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.group_add_outlined, color: accentColor),
                title: const Text('Join a course'),
                subtitle: const Text('Enter a course code'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showJoinDialog();
                },
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                cursorColor: accentColor,
                decoration: InputDecoration(
                  labelText: 'Course Name',
                  labelStyle:
                      TextStyle(color: isDark ? Colors.white70 : Colors.grey),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: accentColor)),
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL',
                  style:
                      TextStyle(color: isDark ? Colors.white70 : Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final nav = Navigator.of(dialogContext);
              try {
                final newCourse = await SupabaseService.createClass(
                  name: nameCtrl.text,
                );
                nav.pop();
                if (!mounted) return;
                setState(() {
                  _drawerCachedCourses.insert(0, newCourse);
                });
                _dashboardKey.currentState?.addCreatedCourse(newCourse);

                CheckMateUi.showTopPrompt(
                    context, 'Course created successfully!',
                    isError: false);
              } catch (e) {
                if (!mounted) return;
                CheckMateUi.showTopPrompt(
                    context, 'Failed to create course: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: buttonTextColor,
            ),
            child: const Text('CREATE'),
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
          maxLength: 8,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          cursorColor: accentColor,
          decoration: InputDecoration(
            labelText: 'Course Code',
            labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
            counterText: "",
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accentColor)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL',
                  style:
                      TextStyle(color: isDark ? Colors.white70 : Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              String input = joinCtrl.text.trim();
              if (input.isEmpty) return;
              if (input.contains('code=')) {
                input = Uri.tryParse(input)?.queryParameters['code'] ?? input;
              }
              final nav = Navigator.of(dialogContext);
              try {
                final course = await SupabaseService.joinClass(input);
                nav.pop();
                if (!mounted) return;
                setState(() {
                  _drawerCachedCourses.insert(0, course);
                });
                _dashboardKey.currentState?.addEnrolledCourse(course);

                CheckMateUi.showTopPrompt(
                    context, 'Joined course: ${course.name}!',
                    isError: false);
              } catch (e) {
                if (!mounted) return;
                final msg = e.toString().replaceAll('Exception: ', '');
                CheckMateUi.showTopPrompt(context, msg,
                    isError: !msg.contains('already enrolled'));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: buttonTextColor,
            ),
            child: const Text('JOIN'),
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
              color: accentColor,
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
          IconButton(
            tooltip: _notificationsOn
                ? 'Mute notifications'
                : 'Enable notifications',
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                _notificationsOn
                    ? Icons.notifications
                    : Icons.notifications_off,
                key: ValueKey<bool>(_notificationsOn),
              ),
            ),
            onPressed: _toggleNotifications,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Settings and profile',
              onPressed: () => _onItemTapped(2),
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: accentColor.withValues(alpha: 0.13),
                child: Icon(Icons.person, color: accentColor, size: 20),
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

                return UserAccountsDrawerHeader(
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF1E1E24) : colorScheme.primary,
                  ),
                  currentAccountPicture: CircleAvatar(
                    backgroundColor: avatarBg,
                    child: Icon(Icons.person, color: contentColor, size: 40),
                  ),
                  accountName: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: contentColor,
                    ),
                  ),
                  accountEmail: Text(
                    email,
                    style: TextStyle(
                      color: contentColor.withValues(alpha: 0.85),
                    ),
                  ),
                );
              },
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
                    padding: EdgeInsets.zero,
                    itemCount: _drawerCachedCourses.length,
                    itemBuilder: (context, index) {
                      final course = _drawerCachedCourses[index];
                      return ListTile(
                        leading: CircleAvatar(
                            backgroundColor:
                                course.adaptiveGradient(context)[0],
                            radius: 12),
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
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
      body: Builder(
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
          ? FloatingActionButton(
              onPressed: _showCourseActions,
              tooltip: 'Create or join a course',
              backgroundColor: accentColor,
              foregroundColor: isDark ? Colors.black : Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
