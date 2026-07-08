import 'package:flutter/material.dart';
import 'ai_questionnaire_screen.dart';

class QuizzesExamsScreen extends StatelessWidget {
  final bool isOwner;
  const QuizzesExamsScreen({super.key, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quizzes & Exams'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExamTile('Midterm Exam', 'June 15, 2026', 'Completed', Colors.green),
          _buildExamTile('Quiz 3: Convolution', 'June 22, 2026', 'Upcoming', Colors.blue),
          _buildExamTile('Final Examination', 'July 15, 2026', 'Scheduled', Colors.red),
        ],
      ),
      floatingActionButton: isOwner ? FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AIQuestionnaireScreen(type: 'Quiz/Exam'),
            ),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildExamTile(String title, String date, String status, Color statusColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ListTile(
          leading: Icon(Icons.quiz, color: statusColor),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Date: $date'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () {},
        ),
      ),
    );
  }
}
