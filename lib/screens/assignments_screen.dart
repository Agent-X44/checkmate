import 'package:flutter/material.dart';
import 'ai_questionnaire_screen.dart';

class AssignmentsScreen extends StatelessWidget {
  final bool isOwner;
  const AssignmentsScreen({super.key, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAssignmentCard('Assignment 1: Matrix Basics', 'Due: June 20, 2026', Colors.orange),
          _buildAssignmentCard('Assignment 2: Fourier Transforms', 'Due: June 25, 2026', Colors.blue),
          _buildAssignmentCard('Project Proposal: Signal Filter', 'Due: July 05, 2026', Colors.purple),
        ],
      ),
      floatingActionButton: isOwner ? FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AIQuestionnaireScreen(type: 'Assignment'),
            ),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildAssignmentCard(String title, String due, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(Icons.assignment, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(due),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {},
      ),
    );
  }
}
