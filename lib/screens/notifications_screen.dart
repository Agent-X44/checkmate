import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/course.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';
import 'learning_materials_screen.dart';
import 'private_chat_screen.dart';
import 'student_insight_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String? initialNotificationId;

  const NotificationsScreen({super.key, this.initialNotificationId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<List<AppNotification>> _notifications =
      NotificationService.streamMine();
  bool _opening = false;
  bool _initialNotificationHandled = false;
  Timer? _initialNotificationTimeout;

  @override
  void initState() {
    super.initState();
    if (widget.initialNotificationId != null) {
      _initialNotificationTimeout = Timer(const Duration(seconds: 8), () {
        if (!mounted || _initialNotificationHandled) return;
        _initialNotificationHandled = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This notification is unavailable.')),
        );
      });
    }
  }

  @override
  void dispose() {
    _initialNotificationTimeout?.cancel();
    super.dispose();
  }

  Future<Course> _loadCourse(String id) async {
    final db = Supabase.instance.client;
    final row = await db
        .from('classes')
        .select('id, name, instructor_id, profiles(name)')
        .eq('id', id)
        .single();
    return Course.fromMap(row,
        isOwner: row['instructor_id'] == db.auth.currentUser?.id);
  }

  Future<void> _open(AppNotification notice) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      Widget destination;
      if (notice.kind == 'result' && notice.examId != null) {
        final exam = await Supabase.instance.client
            .from('exams')
            .select('title, results_released')
            .eq('id', notice.examId!)
            .single();
        if (exam['results_released'] != true) {
          throw StateError('This result has not been released.');
        }
        destination = StudentInsightDetailScreen(
          examId: notice.examId!,
          examTitle: exam['title']?.toString() ?? 'Assessment result',
        );
      } else if (notice.classId != null) {
        final course = await _loadCourse(notice.classId!);
        if (notice.kind == 'announcement') {
          destination = ChatScreen(course: course);
        } else if (notice.kind == 'module_upload') {
          destination = LearningMaterialsScreen(
            isOwner: course.isOwner,
            courseId: course.id,
          );
        } else if (notice.kind == 'message' && notice.studentId != null) {
          final db = Supabase.instance.client;
          final isOwner = course.isOwner;
          final studentName = isOwner
              ? (await db
                          .from('profiles')
                          .select('name')
                          .eq('id', notice.studentId!)
                          .single())['name']
                      ?.toString() ??
                  'Student'
              : course.instructor;
          destination = PrivateChatScreen(
            course: course,
            student: Student(
              id: notice.studentId!,
              name: studentName,
              avatar: studentName.isEmpty ? '?' : studentName[0].toUpperCase(),
            ),
          );
        } else {
          throw StateError('Notification destination is unavailable.');
        }
      } else {
        throw StateError('Notification destination is unavailable.');
      }
      await NotificationService.markRead(notice.id);
      if (mounted) {
        await Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => destination));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open notification: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openInitialNotificationIfPresent(List<AppNotification> notices) {
    final id = widget.initialNotificationId;
    if (id == null || _initialNotificationHandled) return;
    AppNotification? notice;
    for (final item in notices) {
      if (item.id == id) {
        notice = item;
        break;
      }
    }
    if (notice == null) return;
    final notificationToOpen = notice;
    _initialNotificationHandled = true;
    _initialNotificationTimeout?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open(notificationToOpen);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notifications,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  'Could not load notifications. Check your connection and database setup.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notices = snapshot.data!;
          _openInitialNotificationIfPresent(notices);
          if (notices.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: notices.any((n) => n.isUnread)
                        ? () async {
                            try {
                              await NotificationService.markAllRead(notices);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Could not mark notifications read: $error')),
                                );
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Mark all read'),
                  ),
                ),
                Expanded(
                    child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: notices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final notice = notices[index];
                    final icon = switch (notice.kind) {
                      'message' => Icons.chat_bubble_outline,
                      'result' => Icons.assessment_outlined,
                      'module_upload' => Icons.folder_open_outlined,
                      _ => Icons.campaign_outlined,
                    };
                    return Card(
                      elevation: 0,
                      color: notice.isUnread
                          ? colors.primaryContainer.withValues(alpha: 0.35)
                          : colors.surfaceContainerLow,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor:
                              colors.primary.withValues(alpha: 0.13),
                          child: Icon(icon, color: colors.primary),
                        ),
                        title: Text(notice.title,
                            maxLines: 2,
                            style: TextStyle(
                                fontWeight: notice.isUnread
                                    ? FontWeight.bold
                                    : FontWeight.w500)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(notice.body,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                              '${MaterialLocalizations.of(context).formatMediumDate(notice.createdAt)} · ${TimeOfDay.fromDateTime(notice.createdAt).format(context)}',
                              style: TextStyle(
                                  color: colors.onSurfaceVariant, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: notice.isUnread
                            ? CircleAvatar(
                                radius: 4, backgroundColor: colors.primary)
                            : null,
                        onTap: () => _open(notice),
                      ),
                    );
                  },
                )),
              ]),
            ),
          );
        },
      ),
    );
  }
}
