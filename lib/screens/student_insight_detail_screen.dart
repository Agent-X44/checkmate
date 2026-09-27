import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';

/// Provides detailed OMR results and personalized AI recommendations for a specific student.
/// Enforces:
/// - BR-10: Personalized student recommendations (AI)
/// - BR-12: Secure data access via RLS
class StudentInsightDetailScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final String? sheetId;
  final String? studentId;

  const StudentInsightDetailScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    this.sheetId,
    this.studentId,
  });

  @override
  State<StudentInsightDetailScreen> createState() =>
      _StudentInsightDetailScreenState();
}

class _StudentInsightDetailScreenState
    extends State<StudentInsightDetailScreen> {
  bool _isLoading = true;
  bool _isGeneratingInsight = false;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  Future<void> _loadResult() async {
    try {
      final Map<String, dynamic>? res;
      if (widget.sheetId != null) {
        res = await SupabaseService.getResultBySheetId(widget.sheetId!);
      } else {
        res = await SupabaseService.getMyResult(widget.examId);
      }
      
      if (mounted) {
        setState(() {
          _data = res;
          _isLoading = false;
        });

        // If grade exists but insight is null, generate it on-the-fly via AI
        final grade = res?['grade'];
        final insight = res?['insight'];
        if (grade != null &&
            (insight == null || insight['insight_text'] == null)) {
          _generateInsightOnTheFly(grade);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateInsightOnTheFly(Map<String, dynamic> grade) async {
    if (_isGeneratingInsight) return;
    setState(() => _isGeneratingInsight = true);

    try {
      final sheetId = grade['sheet_id']?.toString() ?? '';
      if (sheetId.isEmpty) {
        throw Exception("Missing sheet ID");
      }

      final res = await ApiService.getStudentInsight(
        examId: widget.examId,
        sheetId: sheetId,
        regenerate: true,
      );

      final insightObj = res['insight'];

      if (mounted) {
        setState(() {
          _data = {
            'grade': grade,
            'insight': insightObj,
          };
          _isGeneratingInsight = false;
        });
      }
    } catch (e) {
      debugPrint("AI Insight generation error: $e");
      if (mounted) setState(() => _isGeneratingInsight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grade = _data?['grade'];
    final insightRaw = _data?['insight']?['insight_text'];

    // Parse structured JSON from AI if possible
    Map<String, dynamic>? insightJson;
    if (insightRaw != null) {
      try {
        insightJson = jsonDecode(insightRaw);
      } catch (_) {
        // Fallback to raw text
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.examTitle)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text("Result not available yet."))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                      child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildScoreHeader(grade),
                        const SizedBox(height: 24),
                        const Text("AI MENTOR INSIGHTS",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
                        const Divider(),
                        const SizedBox(height: 12),
                        if (insightJson != null)
                          _buildStructuredInsight(insightJson)
                        else if (_isGeneratingInsight)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text("AI Mentor is analyzing your results...",
                                      textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                              insightRaw ??
                                  "Your AI-powered pedagogical feedback is being generated. Check back soon!",
                              style:
                                  const TextStyle(fontSize: 15, height: 1.5)),
                      ],
                    ),
                  )),
                ),
    );
  }

  Widget _buildScoreHeader(Map<String, dynamic>? grade) {
    if (grade == null) return const SizedBox();
    final pct = grade['percentage'] ?? 0.0;
    final score = grade['score'] ?? 0;
    final total = grade['total_questions'] ?? 0;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: LayoutBuilder(
            builder: (context, constraints) => Flex(
                  direction: constraints.maxWidth < 340
                      ? Axis.vertical
                      : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: pct / 100,
                            strokeWidth: 8,
                            backgroundColor: Colors.white,
                            color: pct >= 75 ? Colors.green : Colors.orange,
                          ),
                        ),
                        Text("${pct.toInt()}%",
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 340 ? 0 : 24,
                      height: constraints.maxWidth < 340 ? 16 : 0,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TOTAL SCORE",
                            style: TextStyle(
                                fontSize: 12, color: Colors.blueGrey)),
                        Text("$score / $total",
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        const Text("Assessment result",
                            style: TextStyle(
                                fontSize: 12, color: Colors.blueGrey)),
                      ],
                    )
                  ],
                )),
      ),
    );
  }

  Widget _buildStructuredInsight(Map<String, dynamic> json) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInsightSection(
            "Performance Summary", json['performanceSummary'], Icons.summarize),
        _buildListSection(
            "Strengths", json['strengths'], Colors.green, Icons.thumb_up),
        _buildListSection("Learning Gaps", json['learningGaps'], Colors.orange,
            Icons.warning),
        _buildListSection("Actionable Steps", json['actionableSteps'],
            Colors.blue, Icons.lightbulb),
      ],
    );
  }

  Widget _buildInsightSection(String title, String? content, IconData icon) {
    if (content == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold))
          ]),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildListSection(
      String title, dynamic list, Color color, IconData icon) {
    if (list == null || list is! List || list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(fontWeight: FontWeight.bold, color: color))
          ]),
          const SizedBox(height: 8),
          ...list.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("• ",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                        child: Text(item.toString(),
                            style: const TextStyle(height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class AnswerEvaluationList extends StatelessWidget {
  final List<Map<String, dynamic>> answers;

  const AnswerEvaluationList({super.key, required this.answers});

  @override
  Widget build(BuildContext context) {
    if (answers.isEmpty) {
      return const Text(
          'Item answers were not saved with this older result. Only its total score is available. New completed scanning sessions include answers and evaluations.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < answers.length; index++)
          _buildItem(context, answers[index], index),
      ],
    );
  }

  Widget _buildItem(
      BuildContext context, Map<String, dynamic> item, int index) {
    final qNum = item['question_number'] ?? (index + 1);
    final qText = item['question_text']?.toString() ?? '';
    final isCorrect = item['isCorrect'] == true;
    final isAmbiguous = item['isAmbiguous'] == true;
    final answer = item['answer']?.toString();
    final correctAnswer = item['correct_answer']?.toString() ?? '';
    final isTf = item['question_type'] == 'TF';
    final options = item['options'] is List ? (item['options'] as List) : [];

    String statusText;
    Color statusColor;
    if (isCorrect) {
      statusText = 'Correct';
      statusColor = Colors.green;
    } else if (isAmbiguous) {
      statusText = 'Needs review';
      statusColor = Colors.orange;
    } else if (answer == null || answer.isEmpty) {
      statusText = 'Unanswered';
      statusColor = Colors.orange;
    } else {
      statusText = 'Incorrect';
      statusColor = Colors.red;
    }

    String studentAnsText;
    if (isAmbiguous) {
      final marks = item['multipleAnswers'] is List
          ? (item['multipleAnswers'] as List).join(', ')
          : 'Multiple';
      studentAnsText = 'Student answer: $marks';
    } else if (answer == null || answer.isEmpty) {
      studentAnsText = 'Student answer: None';
    } else if (isTf) {
      final tfLabel =
          answer == 'A' ? 'True' : (answer == 'B' ? 'False' : answer);
      studentAnsText = 'Student answer: $tfLabel';
    } else {
      String optionVal = '';
      if (options.isNotEmpty && answer.length == 1) {
        final code = answer.codeUnitAt(0) - 65;
        if (code >= 0 && code < options.length) {
          optionVal = '. ${options[code]}';
        }
      }
      studentAnsText = 'Student answer: $answer$optionVal';
    }

    String correctAnsText = '';
    if (isTf) {
      final tfLabel = correctAnswer == 'A'
          ? 'True'
          : (correctAnswer == 'B' ? 'False' : correctAnswer);
      correctAnsText = 'Correct answer: $tfLabel';
    } else {
      correctAnsText = 'Correct answer: $correctAnswer';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Question $qNum',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(statusText,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: statusColor)),
              ],
            ),
            if (qText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(qText, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 8),
            Text(studentAnsText, style: const TextStyle(fontSize: 13)),
            if (!isCorrect && correctAnsText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(correctAnsText,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}
