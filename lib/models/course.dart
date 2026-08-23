import 'package:flutter/material.dart';

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
    // Generate a consistent gradient based on the ID string
    final idHash = map['id'].toString().hashCode;
    final List<List<Color>> presets = [
      [Colors.blue.shade700, Colors.blue.shade400],
      [Colors.indigo.shade700, Colors.indigo.shade400],
      [Colors.teal.shade700, Colors.teal.shade400],
      [Colors.orange.shade700, Colors.orange.shade400],
      [Colors.purple.shade700, Colors.purple.shade400],
    ];
    final gradient = presets[idHash % presets.length];

    return Course(
      id: map['id'],
      code: map['code'] ?? 'N/A',
      name: map['name'] ?? 'Untitled Course',
      instructor: map['profiles']?['name'] ?? 'Instructor',
      averageGrade: 'N/A', // Calculated later
      gradient: gradient,
      joinCode: map['code'] ?? '', // Using code as join code for simplicity
      isOwner: isOwner,
    );
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
