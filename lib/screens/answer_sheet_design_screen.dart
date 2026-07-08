import 'package:flutter/material.dart';

class AnswerSheetDesignScreen extends StatelessWidget {
  const AnswerSheetDesignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Answer Sheet Design'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildDesignCard(
                  context,
                  'Standard 50 Questions',
                  'Standard A4 layout with 50 multiple-choice questions.',
                  Icons.description,
                ),
                _buildDesignCard(
                  context,
                  'Compact 100 Questions',
                  'Two-column layout for longer exams.',
                  Icons.grid_view,
                ),
                _buildDesignCard(
                  context,
                  'Quick Quiz (20 Questions)',
                  'Small format for short assessments.',
                  Icons.article,
                ),
                _buildDesignCard(
                  context,
                  'Custom Feedback Sheet',
                  'Includes space for written comments and grading.',
                  Icons.assignment_ind,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Placeholder for PDF export function
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Exporting to PDF... (Functionality coming soon)')),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text(
                  'EXPORT TO PDF',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignCard(BuildContext context, String title, String subtitle, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.radio_button_off),
        onTap: () {
          // Placeholder for selection logic
        },
      ),
    );
  }
}
