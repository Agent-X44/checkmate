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

  const StudentInsightDetailScreen({
    super.key,
    required this.examId,
    required this.examTitle,
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
      final res = await SupabaseService.getMyResult(widget.examId);
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
      final user = SupabaseService.currentUser;
      final studentName = user?.userMetadata?['name'] ??
          user?.email?.split('@')[0] ??
          'Student';
      final score = (grade['score'] as num?)?.toInt() ?? 0;
      final total = (grade['total_questions'] as num?)?.toInt() ?? 0;

      final res = await ApiService.getStudentInsight(
        studentName: studentName,
        score: score,
        total: total,
      );

      final insightObj = res['insight'];
      final jsonText = jsonEncode(insightObj);

      // Save to database if user is authenticated
      if (user != null) {
        try {
          await SupabaseService.client.from('ai_insights').upsert({
            'exam_id': widget.examId,
            'student_id': user.id,
            'insight_text': jsonText,
          });
        } catch (e) {
          debugPrint("Failed to persist AI insight: $e");
        }
      }

      if (mounted) {
        setState(() {
          _data = {
            'grade': grade,
            'insight': {'insight_text': jsonText},
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
