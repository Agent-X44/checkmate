import 'package:flutter/material.dart';
import '../utils/ui_utils.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  String text;
  final DateTime timestamp;
  bool isEdited;
  DateTime? editedTimestamp;

  ChatMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isEdited = false,
    this.editedTimestamp,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  bool getIsMe(bool isCurrentViewerOwner) {
    if (isCurrentViewerOwner) {
      return senderId == 'instructor';
    } else {
      return senderId != 'instructor';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'isEdited': isEdited,
    'editedTimestamp': editedTimestamp?.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    senderId: json['senderId'] ?? (json['sender'] == 'Me' ? 'instructor' : 'student'),
    senderName: json['senderName'] ?? json['sender'] ?? 'User',
    text: json['text'] ?? '',
    timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
    isEdited: json['isEdited'] ?? false,
    editedTimestamp: json['editedTimestamp'] != null ? DateTime.parse(json['editedTimestamp']) : null,
  );
}

class ClassComment {
  final String id;
  final String authorName;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ClassComment({
    required this.id,
    required this.authorName,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorName': authorName,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'isMe': isMe,
  };

  factory ClassComment.fromJson(Map<String, dynamic> json) => ClassComment(
    id: json['id'] ?? '',
    authorName: json['authorName'] ?? 'User',
    text: json['text'] ?? '',
    timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
    isMe: json['isMe'] ?? false,
  );
}

class StreamPost {
  final String id;
  final String authorName;
  final String authorRole;
  final String? title;
  String content;
  final DateTime timestamp;
  DateTime? editedTimestamp;
  final String postType; // 'announcement', 'material', 'assignment', 'message'
  String? attachmentName;
  String? attachmentType;
  final List<ClassComment> comments;
  bool allowComments;
  final bool isMe;

  StreamPost({
    required this.id,
    required this.authorName,
    this.authorRole = 'Instructor',
    this.title,
    required this.content,
    required this.timestamp,
    this.editedTimestamp,
    this.postType = 'announcement',
    this.attachmentName,
    this.attachmentType,
    List<ClassComment>? comments,
    this.allowComments = true,
    required this.isMe,
  }) : comments = comments ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorName': authorName,
    'authorRole': authorRole,
    'title': title,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'editedTimestamp': editedTimestamp?.toIso8601String(),
    'postType': postType,
    'attachmentName': attachmentName,
    'attachmentType': attachmentType,
    'allowComments': allowComments,
    'isMe': isMe,
    'comments': comments.map((c) => c.toJson()).toList(),
  };

  factory StreamPost.fromJson(Map<String, dynamic> json) => StreamPost(
    id: json['id'] ?? '',
    authorName: json['authorName'] ?? 'Instructor',
    authorRole: json['authorRole'] ?? 'Instructor',
    title: json['title'],
    content: json['content'] ?? '',
    timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
    editedTimestamp: json['editedTimestamp'] != null ? DateTime.parse(json['editedTimestamp']) : null,
    postType: json['postType'] ?? 'announcement',
    attachmentName: json['attachmentName'],
    attachmentType: json['attachmentType'],
    allowComments: json['allowComments'] ?? true,
    isMe: json['isMe'] ?? false,
    comments: (json['comments'] as List? ?? []).map((c) => ClassComment.fromJson(c)).toList(),
  );
}

class PrivateChat {
  final String studentId;
  final List<ChatMessage> messages;

  PrivateChat({
    required this.studentId,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];
}

class Student {
  final String id;
  final String name;
  final String avatar;

  Student({required this.id, required this.name, required this.avatar});
}

class Course {
  final String id;
  final String code;
  final String name;
  final String instructor;
  final String averageGrade;
  final List<Color> gradient;
  final bool isOwner;
  final List<ChatMessage> groupMessages;
  final List<StreamPost> streamPosts;
  final List<Student> enrolledStudents;
  final Map<String, PrivateChat> privateChats;
  bool globalCanStudentReply;
  final String joinCode;

  Course({
    required this.id,
    required this.code,
    required this.name,
    required this.instructor,
    required this.averageGrade,
    required this.gradient,
    required this.joinCode,
    this.isOwner = false,
    this.globalCanStudentReply = true,
    List<ChatMessage>? groupMessages,
    List<StreamPost>? streamPosts,
    List<Student>? enrolledStudents,
    Map<String, PrivateChat>? privateChats,
  })  : groupMessages = groupMessages ?? [],
        streamPosts = streamPosts ?? [],
        enrolledStudents = enrolledStudents ?? [],
        privateChats = privateChats ?? {};

  factory Course.fromMap(Map<String, dynamic> map, {required bool isOwner}) {
    final String courseId = map['id']?.toString() ?? '';
    final gradient = CheckMateUi.generateGradient(courseId);

    return Course(
      id: courseId,
      code: map['code'] ?? 'N/A',
      name: map['name'] ?? 'Untitled Course',
      instructor: map['profiles']?['name'] ?? 'Instructor',
      averageGrade: 'N/A', // Calculated later
      gradient: gradient,
      joinCode: map['code'] ?? '', // Using code as join code for simplicity
      isOwner: isOwner,
    );
  }

  /// Returns theme-adaptive gradient colors:
  /// Light mode -> Deep, pigmented tones
  /// Dark mode -> Lighter, high-exposure luminous tones
  List<Color> adaptiveGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CheckMateUi.generateGradient(id, isDark: isDark);
  }
}

String generateJoinCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(
      6,
      (index) => chars[(DateTime.now().microsecondsSinceEpoch + index) %
          chars.length]).join();
}

// Empty global state for production use
List<Course> globalDummyCourses = [];
