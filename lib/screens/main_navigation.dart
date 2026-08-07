import 'package:flutter/material.dart';
import '../models/course.dart';
import 'dashboard_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'course_dashboard_screen.dart';
import '../main.dart'; // To access globalCameras and CheckmateApp (for logout)

class MainNavigation extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<bool> onThemeChanged;

  const MainNavigation({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isFabExpanded = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
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
                decoration: const InputDecoration(labelText: 'Course Code')),
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Course Name')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
              setState(() {
                globalDummyCourses.insert(
                    0,
                    Course(
                      id: DateTime.now().toString(),
                      code: codeCtrl.text,
                      name: nameCtrl.text,
                      instructor: 'Hannah Grace Narte',
                      averageGrade: 'N/A',
                      isOwner: true,
                      joinCode: generateJoinCode(),
                      gradient: [
                        Colors.orange.shade700,
                        Colors.orange.shade400
                      ],
                    ));
              });
              Navigator.pop(context);
              _toggleFab();
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    final joinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a Course'),
        content: TextField(
          controller: joinCtrl,
          decoration: const InputDecoration(labelText: 'Course Code'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                globalDummyCourses.add(Course(
                  id: DateTime.now().toString(),
                  code: 'JOINED',
                  name: 'Course Code: ${joinCtrl.text}',
                  instructor: 'External Instructor',
                  averageGrade: 'N/A',
                  isOwner: false,
                  joinCode: joinCtrl.text,
                  gradient: [Colors.purple.shade700, Colors.purple.shade400],
                ));
              });
              Navigator.pop(context);
              _toggleFab();
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const DashboardScreen(),
      ScannerScreen(cameras: globalCameras, isActive: _selectedIndex == 1),
      SettingsScreen(
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
        onLogout: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const CheckmateApp()),
            (route) => false,
          );
        },
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Checkmate'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
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
            UserAccountsDrawerHeader(
              decoration:
                  BoxDecoration(color: Theme.of(context).colorScheme.primary),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 40),
              ),
              accountName: const Text('Hannah Grace Narte'),
              accountEmail: const Text('Academic Profile'),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: globalDummyCourses.length,
                itemBuilder: (context, index) {
                  final course = globalDummyCourses[index];
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
                            onCourseDeleted: () => setState(() =>
                                globalDummyCourses
                                    .removeWhere((c) => c.id == course.id)),
                          ),
                        ),
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
              onTap: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const CheckmateApp()),
                  (route) => false,
                );
              },
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
        selectedItemColor: Theme.of(context).colorScheme.primary,
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
                          color: Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_add, color: Colors.black),
                            SizedBox(width: 8),
                            Text('Join Course',
                                style: TextStyle(
                                    color: Colors.black,
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
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(_isFabExpanded ? 16 : 28),
                ),
                child: InkWell(
                  onTap: _isFabExpanded ? _showCreateDialog : _toggleFab,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isFabExpanded ? Icons.add_box : Icons.add,
                          color: Colors.black),
                      if (_isFabExpanded) ...[
                        const SizedBox(width: 8),
                        const Text('Create Course',
                            style: TextStyle(
                                color: Colors.black,
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
