import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class StudentInsightDetailScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const StudentInsightDetailScreen({
    super.key,
    required this.examId,
    required this.examTitle,
  });

  @override
  State<StudentInsightDetailScreen> createState() => _StudentInsightDetailScreenState();
}

class _StudentInsightDetailScreenState extends State<StudentInsightDetailScreen> {
  bool _isLoading = true;
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildScoreHeader(grade),
                      const SizedBox(height: 24),
                      const Text("AI MENTOR INSIGHTS", 
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.blueAccent)),
                      const Divider(),
                      const SizedBox(height: 12),
                      if (insightJson != null)
                        _buildStructuredInsight(insightJson)
                      else
                        Text(insightRaw ?? "Your AI-powered pedagogical feedback is being generated. Check back soon!", 
                          style: const TextStyle(fontSize: 15, height: 1.5)),
                    ],
                  ),
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
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: CircularProgressIndicator(
                    value: pct / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white,
                    color: pct >= 75 ? Colors.green : Colors.orange,
                  ),
                ),
                Text("${pct.toInt()}%", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("TOTAL SCORE", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                Text("$score / $total", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const Text("Keep up the great work!", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredInsight(Map<String, dynamic> json) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInsightSection("Performance Summary", json['performanceSummary'], Icons.summarize),
        _buildListSection("Strengths", json['strengths'], Colors.green, Icons.thumb_up),
        _buildListSection("Learning Gaps", json['learningGaps'], Colors.orange, Icons.warning),
        _buildListSection("Actionable Steps", json['actionableSteps'], Colors.blue, Icons.lightbulb),
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
          Row(children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildListSection(String title, dynamic list, Color color, IconData icon) {
    if (list == null || list is! List || list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color))]),
          const SizedBox(height: 8),
          ...list.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: Text(item.toString(), style: const TextStyle(height: 1.4))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
