import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/pdf_generator.dart';
import '../models/omr/bubble_sheet_template.dart';
import 'ai_questionnaire_screen.dart';
import 'student_insight_detail_screen.dart';

class QuizzesExamsScreen extends StatefulWidget {
  final bool isOwner;
  final String courseId;

  const QuizzesExamsScreen({
    super.key,
    required this.isOwner,
    required this.courseId,
  });

  @override
  State<QuizzesExamsScreen> createState() => _QuizzesExamsScreenState();
}

class _QuizzesExamsScreenState extends State<QuizzesExamsScreen> {
  // Demo Template aligned with 50_questions.png
  static const demoTemplate = BubbleSheetTemplate(
    name: "Standard 50-Question",
    answerRegions: [Rect.fromLTRB(0.1, 0.2, 0.45, 0.9), Rect.fromLTRB(0.55, 0.2, 0.9, 0.9)],
    totalQuestions: 50,
    choicesPerQuestion: 4,
    columns: 2,
  );

  Future<void> _approveExam(String examId) async {
    try {
      await SupabaseService.approveExam(examId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exam approved successfully!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Approval failed: $e")));
      }
    }
  }

  Future<void> _generateSheets(String examTitle) async {
    try {
      // 1. Fetch real enrolled students
      final studentsData = await SupabaseService.getEnrolledStudents(widget.courseId);
      final List<String> names = studentsData
          .map((s) => (s['profiles'] as Map)['name']?.toString() ?? "Student")
          .toList();

      if (names.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No students enrolled in this course yet.")));
        }
        return;
      }

      // 2. Trigger PDF Generator
      await PdfGenerator.generateAndPrint(
        demoTemplate,
        studentNames: names,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Generation failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quizzes & Exams')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.streamExams(widget.courseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final exams = snapshot.data ?? [];
          if (exams.isEmpty) {
            return const Center(
              child: Text("No assessments yet. Create one with AI!", style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: exams.length,
            itemBuilder: (context, index) {
              final exam = exams[index];
              final isApproved = exam['is_approved'] == true;
              final status = exam['status'] ?? 'Draft';
              
              Color statusColor = Colors.orange;
              if (isApproved) statusColor = Colors.green;
              if (exam['results_released'] == true) statusColor = Colors.blue;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.quiz, color: statusColor),
                        title: Text(exam['title'] ?? 'Untitled Quiz', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Status: $status'),
                        trailing: isApproved 
                          ? const Icon(Icons.verified, color: Colors.green)
                          : const Icon(Icons.pending_actions, color: Colors.orange),
                        onTap: (!widget.isOwner && exam['results_released'] == true) 
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentInsightDetailScreen(
                                  examId: exam['id'],
                                  examTitle: exam['title'] ?? 'Quiz',
                                ),
                              ),
                            )
                          : null,
                      ),
                      if (widget.isOwner) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!isApproved)
                                TextButton.icon(
                                  onPressed: () => _approveExam(exam['id']),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text("APPROVE"),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () => _generateSheets(exam['title']),
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text("GENERATE SHEETS"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade50,
                                    foregroundColor: Colors.blue.shade800,
                                  ),
                                ),
                            ],
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AIQuestionnaireScreen(
                      type: 'Quiz/Exam',
                      classId: widget.courseId,
                    ),
                  ),
                );
              },
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
