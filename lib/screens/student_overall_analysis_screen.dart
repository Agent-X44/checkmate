import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Personal AI analysis across all of the student's released results.
/// Enforces:
/// - BR-10: Personalized student recommendations (AI)
/// - BR-12: Secure data access via RLS
class StudentOverallAnalysisScreen extends StatefulWidget {
  final String? studentId;
  final String? classId;
  final String? studentName;
  const StudentOverallAnalysisScreen({
    super.key,
    this.studentId,
    this.classId,
    this.studentName,
  });

  @override
  State<StudentOverallAnalysisScreen> createState() =>
      _StudentOverallAnalysisScreenState();
}

class _StudentOverallAnalysisScreenState
    extends State<StudentOverallAnalysisScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getStudentOverallAnalysis(
        studentId: widget.studentId,
        classId: widget.classId,
      );
      final analysis = data['analysis'];
      if (data['status'] != 'no_results' &&
          (analysis is! Map ||
              analysis['performanceSummary'] is! String ||
              (analysis['performanceSummary'] as String).trim().isEmpty ||
              analysis['actionableSteps'] is! List ||
              (analysis['actionableSteps'] as List).isEmpty)) {
        throw const FormatException('The analysis response is incomplete.');
      }
      if (mounted) setState(() => _data = data);
    } catch (error) {
      debugPrint('Student overall analysis failed: $error');
      if (mounted) {
        setState(() => _error =
            'Could not load your personal analysis. Check your connection and retry.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noResults = _data?['status'] == 'no_results';
    final isSummary = _data?['source'] == 'summary';
    final count = _data?['sample_count'];
    final analysis = _data?['analysis'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.studentName == null
              ? 'My Performance Analysis'
              : '${widget.studentName} · Performance')),
      body: _isLoading
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                    widget.studentName == null
                        ? 'Analyzing your released results...'
                        : 'Analyzing saved course results...',
                    textAlign: TextAlign.center),
              ]),
            ))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _error != null || noResults
                      ? Column(
                          children: [
                            Text(_error ??
                                (widget.studentName == null
                                    ? 'No released results yet. Your personal analysis will appear here once an instructor releases your results.'
                                    : 'No saved results for this student in this course yet.')),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: _load, child: const Text('Retry')),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (count != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(count == 1
                                    ? 'Based on 1 ${widget.studentName == null ? 'released' : 'saved'} result.'
                                    : 'Based on $count ${widget.studentName == null ? 'released' : 'saved'} results.'),
                              ),
                            if (isSummary)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                    'Score-based summary • AI is temporarily unavailable.'),
                              ),
                            _buildInsightSection(
                              'PERFORMANCE SUMMARY',
                              analysis?['performanceSummary']?.toString(),
                              Icons.summarize,
                              Theme.of(context).colorScheme.primary,
                            ),
                            _buildTopicEvidence(),
                            const SizedBox(height: 20),
                            _buildListSection(
                                'STRENGTHS',
                                analysis?['strengths'],
                                Colors.green,
                                Icons.thumb_up),
                            const SizedBox(height: 20),
                            _buildListSection(
                                'LEARNING GAPS',
                                analysis?['learningGaps'],
                                Colors.orange,
                                Icons.warning),
                            const SizedBox(height: 20),
                            _buildListSection(
                                'ACTIONABLE STEPS',
                                analysis?['actionableSteps'],
                                Colors.blue,
                                Icons.lightbulb),
                            const SizedBox(height: 12),
                            if (isSummary)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry AI analysis'),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }

  Widget _buildInsightSection(
      String title, String? content, IconData icon, Color color) {
    if (content == null || content.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1.2))),
            ]),
            const Divider(height: 30),
            Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicEvidence() {
    final metrics = _data?['metrics'];
    if (metrics is! Map || metrics['topics'] is! Map) {
      return const SizedBox.shrink();
    }
    final topics = Map<String, dynamic>.from(metrics['topics']);
    if (topics.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TOPIC RESULTS',
                style:
                    TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            ...topics.entries.map((entry) {
              final counts = entry.value is Map ? entry.value as Map : const {};
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${entry.key}: ${counts['correct'] ?? 0}/${counts['total'] ?? 0} correct'),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection(
      String title, dynamic list, Color color, IconData icon) {
    if (list == null || list is! List || list.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: color))),
            ]),
            const Divider(height: 30),
            ...list.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                          child: Text(item.toString(),
                              style:
                                  const TextStyle(fontSize: 16, height: 1.4))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
