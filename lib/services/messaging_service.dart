import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';

class MessagingService {
  static SupabaseClient get _db => Supabase.instance.client;

  static String get _userId {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in to use course announcements.');
    return id;
  }

  static Future<List<StreamPost>> loadStreamPosts(String courseId) async {
    _userId;
    final rows = await _db
        .from('class_announcements')
        .select(
            'id, author_id, content, allow_comments, created_at, updated_at, '
            'profiles(name), '
            'announcement_comments(id, author_id, content, created_at, profiles(name))')
        .eq('class_id', courseId)
        .order('created_at', ascending: false);
    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final author = row['profiles'] as Map?;
      final comments =
          (row['announcement_comments'] as List? ?? []).map((rawComment) {
        final comment = Map<String, dynamic>.from(rawComment as Map);
        final profile = comment['profiles'] as Map?;
        return ClassComment(
          id: comment['id'].toString(),
          authorName: profile?['name']?.toString() ?? 'Student',
          text: comment['content']?.toString() ?? '',
          timestamp: DateTime.parse(comment['created_at'].toString()).toLocal(),
          isMe: comment['author_id'] == _userId,
        );
      }).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return StreamPost(
        id: row['id'].toString(),
        authorName: author?['name']?.toString() ?? 'Instructor',
        authorRole: 'Instructor',
        content: row['content']?.toString() ?? '',
        timestamp: DateTime.parse(row['created_at'].toString()).toLocal(),
        editedTimestamp: row['updated_at'] == null
            ? null
            : DateTime.parse(row['updated_at'].toString()).toLocal(),
        allowComments: row['allow_comments'] == true,
        isMe: row['author_id'] == _userId,
        comments: comments,
      );
    }).toList();
  }

  static Future<void> createAnnouncement(
      String courseId, String content, bool allowComments) async {
    final userId = _userId;
    final owned = await _db
        .from('classes')
        .select('id')
        .eq('id', courseId)
        .eq('instructor_id', userId)
        .maybeSingle();
    if (owned == null) throw StateError('Only the instructor can announce.');
    await _db.from('class_announcements').insert({
      'class_id': courseId,
      'author_id': userId,
      'content': content.trim(),
      'allow_comments': allowComments,
    });
  }

  static Future<void> updateAnnouncement(
      String courseId, String postId, String content) async {
    final row = await _db
        .from('class_announcements')
        .update({
          'content': content.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', postId)
        .eq('class_id', courseId)
        .eq('author_id', _userId)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Announcement could not be updated.');
  }

  static Future<void> setAnnouncementCommentsAllowed(
      String courseId, String postId, bool allowed) async {
    final row = await _db
        .from('class_announcements')
        .update({'allow_comments': allowed})
        .eq('id', postId)
        .eq('class_id', courseId)
        .eq('author_id', _userId)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Comment setting could not be changed.');
  }

  static Future<void> deleteAnnouncement(String courseId, String postId) async {
    final row = await _db
        .from('class_announcements')
        .delete()
        .eq('id', postId)
        .eq('class_id', courseId)
        .eq('author_id', _userId)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Announcement could not be deleted.');
  }

  static Future<void> addAnnouncementComment(
      String postId, String content) async {
    await _db.from('announcement_comments').insert({
      'announcement_id': postId,
      'author_id': _userId,
      'content': content.trim(),
    });
  }

  static ChatMessage _chatMessage(Map<String, dynamic> row, String studentId,
      String studentName, String instructorName) {
    final senderId = row['sender_id'].toString();
    return ChatMessage(
      id: row['id'].toString(),
      senderId: senderId,
      senderName: senderId == studentId ? studentName : instructorName,
      text: row['content']?.toString() ?? '',
      timestamp: DateTime.parse(row['created_at'].toString()).toLocal(),
      isEdited: row['edited_at'] != null,
      editedTimestamp: row['edited_at'] == null
          ? null
          : DateTime.parse(row['edited_at'].toString()).toLocal(),
    );
  }

  static Stream<List<ChatMessage>> streamPrivateChat(String courseId,
      String studentId, String studentName, String instructorName) {
    _userId;
    return _db
        .from('private_messages')
        .stream(primaryKey: ['id'])
        .eq('student_id', studentId)
        .map((rows) => rows
            .where((row) => row['class_id'] == courseId)
            .map((row) =>
                _chatMessage(row, studentId, studentName, instructorName))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  }

  static Future<void> sendPrivateMessage(
      String courseId, String studentId, String content) async {
    await _db.from('private_messages').insert({
      'class_id': courseId,
      'student_id': studentId,
      'sender_id': _userId,
      'content': content.trim(),
    });
  }

  static Future<void> editPrivateMessage(
      String messageId, String content) async {
    final row = await _db
        .from('private_messages')
        .update({
          'content': content.trim(),
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId)
        .eq('sender_id', _userId)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Message could not be updated.');
  }

  static Future<void> deletePrivateMessage(String messageId) async {
    final row = await _db
        .from('private_messages')
        .delete()
        .eq('id', messageId)
        .eq('sender_id', _userId)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Message could not be removed.');
  }
}
