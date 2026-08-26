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

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isFabExpanded = false;
  bool _notificationsOn = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _opacityAnimation;

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
        content: const Text('Notifications are currently disabled. Please enable them in settings to receive updates.'),
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
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (_isFabExpanded) {
        _isFabExpanded = false;
        _animationController.reverse();
      }
    });
  }

  void _toggleFab() {
    setState(() {
      _isFabExpanded = !_isFabExpanded;
      if (_isFabExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _showCreateDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: codeCtrl,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                cursorColor: accentColor,
                decoration: InputDecoration(
                  labelText: 'Course Code',
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
                  counterText: "",
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
                )),
            TextField(
                controller: nameCtrl,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                cursorColor: accentColor,
                decoration: InputDecoration(
                  labelText: 'Course Name',
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
              
              try {
                await SupabaseService.createClass(
                  name: nameCtrl.text,
                  code: codeCtrl.text,
                );
                if (mounted) {
                  Navigator.pop(context);
                  _toggleFab();
                  CheckMateUi.showTopPrompt(context, 'Course created successfully!', isError: false);
                }
              } catch (e) {
                if (mounted) {
                  CheckMateUi.showTopPrompt(context, 'Failed to create course: $e');
                }
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
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    final joinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (joinCtrl.text.isEmpty) return;
              try {
                await SupabaseService.joinClass(joinCtrl.text);
                if (mounted) {
                  Navigator.pop(context);
                  _toggleFab();
                  CheckMateUi.showTopPrompt(context, 'Joined course successfully!', isError: false);
                }
              } catch (e) {
                if (mounted) {
                  // Explicitly check for class not found to give a better message
                  final msg = e.toString().contains('single') || e.toString().contains('JSON object') 
                    ? 'Course code invalid. Please check and try again.' 
                    : 'Failed to join: $e';
                  CheckMateUi.showTopPrompt(context, msg);
                }
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
    final accentColor = isDark ? theme.colorScheme.secondary : theme.colorScheme.primary;

    final List<Widget> screens = [
      const DashboardScreen(),
      ScannerScreen(cameras: globalCameras, isActive: _selectedIndex == 1),
      SettingsScreen(
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('CheckMate'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                _notificationsOn ? Icons.notifications : Icons.notifications_off,
                key: ValueKey<bool>(_notificationsOn),
                color: Colors.white,
              ),
            ),
            onPressed: _toggleNotifications,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = 2),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 20),
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
                
                return UserAccountsDrawerHeader(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
                  currentAccountPicture: const CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 40),
                  ),
                  accountName: Text(name),
                  accountEmail: Text(email),
                );
              },
            ),
            Expanded(
              child: StreamBuilder(
                stream: SupabaseService.streamCreatedCourses(),
                builder: (context, _) {
                  return StreamBuilder(
                    stream: SupabaseService.streamEnrolledCourses(),
                    builder: (context, _) {
                      return FutureBuilder<List<Course>>(
                        future: Future.wait([
                          SupabaseService.getCreatedCoursesDetails(),
                          SupabaseService.getEnrolledCoursesDetails(),
                        ]).then((results) => [...results[0], ...results[1]]),
                        builder: (context, snapshot) {
                          final courses = snapshot.data ?? [];

                          if (courses.isEmpty) {
                            return const Center(child: Text("No courses", style: TextStyle(color: Colors.grey)));
                          }

                          return ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: courses.length,
                            itemBuilder: (context, index) {
                              final course = courses[index];
                              return ListTile(
                                leading: CircleAvatar(
                                    backgroundColor: course.gradient[0], radius: 12),
                                title: Text(course.code),
                                subtitle: Text(course.name, maxLines: 1),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CourseDashboardScreen(
                                        course: course,
                                        onCourseDeleted: () {}, // Handled by stream
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
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
      body: GestureDetector(
        onTap: () {
          if (_isFabExpanded) {
            setState(() {
              _isFabExpanded = false;
              _animationController.reverse();
            });
          }
        },
        child: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.secondary
            : Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: Visibility(
        visible: _selectedIndex == 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _showJoinDialog,
                      child: Container(
                        height: 56,
                        width: 170,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_add, color: isDark ? Colors.black : Colors.white),
                            const SizedBox(width: 8),
                            Text('Join Course',
                                style: TextStyle(
                                    color: isDark ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _toggleFab,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: 56,
                width: _isFabExpanded ? 170 : 56,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(_isFabExpanded ? 16 : 28),
                ),
                child: InkWell(
                  onTap: _isFabExpanded ? _showCreateDialog : _toggleFab,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isFabExpanded ? Icons.add_box : Icons.add,
                          color: isDark ? Colors.black : Colors.white),
                      if (_isFabExpanded) ...[
                        const SizedBox(width: 8),
                        Text('Create Course',
                            style: TextStyle(
                                color: isDark ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
