import 'package:checkmate/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationService', () {
    test('uses stable non-negative notification IDs', () {
      final first = NotificationService.notificationId('notification-123');
      final second = NotificationService.notificationId('notification-123');

      expect(first, second);
      expect(first, greaterThanOrEqualTo(0));
      expect(
        NotificationService.notificationId('notification-124'),
        isNot(first),
      );
    });

    test('parses uploaded-material notification metadata', () {
      final notification = AppNotification.fromMap({
        'id': 'notice-1',
        'kind': 'module_upload',
        'title': 'New learning material',
        'body': 'Week 2 slides.pdf',
        'class_id': 'class-1',
        'exam_id': null,
        'related_student_id': null,
        'created_at': '2026-10-04T10:00:00Z',
        'read_at': null,
      });

      expect(notification.kind, 'module_upload');
      expect(notification.classId, 'class-1');
      expect(notification.isUnread, isTrue);
    });
  });
}
