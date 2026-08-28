import 'package:flutter/material.dart';
import '../utils/ui_utils.dart';

class ChatMessage {
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });
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
    List<Student>? enrolledStudents,
    Map<String, PrivateChat>? privateChats,
  })  : groupMessages = groupMessages ?? [],
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
