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
}

String generateJoinCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(6, (index) => chars[(DateTime.now().microsecondsSinceEpoch + index) % chars.length]).join();
}

// Updated global state to show a MIX of roles for the same user
List<Course> globalDummyCourses = [
  // User is the TEACHER here
  Course(
    id: '1',
    code: 'CPE 311',
    name: 'Digital Signal Processing',
    instructor: 'Hilda Santos',
    averageGrade: '85%',
    isOwner: true,
    joinCode: 'DSP789',
    gradient: [Colors.blue.shade700, Colors.blue.shade400],
    enrolledStudents: [
      Student(id: 's1', name: 'John Doe', avatar: 'JD'),
      Student(id: 's2', name: 'Jane Smith', avatar: 'JS'),
    ],
  ),
  // User is the STUDENT here
  Course(
    id: '3',
    code: 'CPE 411',
    name: 'Embedded Systems Design',
    instructor: 'Dr. Alan Turing', 
    averageGrade: '78%',
    isOwner: false,
    joinCode: 'EMB123',
    gradient: [Colors.teal.shade700, Colors.teal.shade400],
    enrolledStudents: [
      Student(id: 'me', name: 'Hilda Santos', avatar: 'HS'),
    ],
  ),
  // User is the TEACHER here
  Course(
    id: '2',
    code: 'CPE 321',
    name: 'Computer Networks & Security',
    instructor: 'Hilda Santos',
    averageGrade: '92%',
    isOwner: true,
    joinCode: 'NET555',
    gradient: [Colors.indigo.shade700, Colors.indigo.shade400],
    enrolledStudents: [
      Student(id: 's1', name: 'John Doe', avatar: 'JD'),
    ],
  ),
];
