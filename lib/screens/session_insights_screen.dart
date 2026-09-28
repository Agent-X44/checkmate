import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';

/// Displays class-wide AI pedagogical insights and teaching recommendations.
/// Enforces:
/// - BR-09: Class-wide pedagogical insights (AI)
/// - BR-11: Controlled release to students
class SessionInsightsScreen extends StatefulWidget {
  final String examId;
  const SessionInsightsScreen({super.key, required this.examId});

  @override
  State<SessionInsightsScreen> createState() => _SessionInsightsScreenState();
}

class _SessionInsightsScreenState extends State<SessionInsightsScreen> {
  bool _isLoading = true;
  bool _isReleasing = false;
  String? _error;
  Map<String, dynamic>? _insights;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInsights() async {
    try {
      final data = await ApiService.analyzeClass(widget.examId);

      // Check if backend returned a "Processing" status instead of data
      if (data.containsKey('status') && data['status'] == 'Processing') {
        _startPolling();
      } else {
        setState(() {
          _insights = data;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load saved class results.';
          _isLoading = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final data = await ApiService.analyzeClass(widget.examId);
        if (data.containsKey('analysis') && data['analysis'] != null) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _insights = data;
              _isLoading = false;
            });
          }
        }
      } catch (_) {
        // Continue polling
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Class Analysis")),
      body: _isLoading
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      const Text("Llama 3.1 is analyzing results...",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(
                          "This happens in the background to prevent timeouts.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  )))
          : _error != null || _insights?['status'] == 'no_results'
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error ??
                      'No saved results are available for analysis yet.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _loadInsights();
                      },
                      child: const Text('Retry')),
                ]))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                      child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInsightCard(
                            "PEDAGOGICAL INSIGHTS",
                            _insights?['analysis']?['insights'] ??
                                "Analysis unavailable.",
                            Icons.psychology),
                        const SizedBox(height: 20),
                        _buildInsightCard(
                            "TEACHING RECOMMENDATIONS",
                            _insights?['analysis']?['recommendations'] ??
                                "Review flagged questions manually.",
                            Icons.school),
                        const SizedBox(height: 20),
                        _buildEvidence(),
                        const SizedBox(height: 40),
                        const Text("CONTROLLED RELEASE",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _isReleasing ? null : _releaseResults,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 60),
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                          ),
                          child: _isReleasing
                              ? CircularProgressIndicator(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary)
                              : const Text("RELEASE RESULTS TO STUDENTS",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )),
                ),
    );
  }

  Widget _buildInsightCard(String title, String content, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              ],
            ),
            const Divider(height: 30),
            Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidence() {
    final metrics = _insights?['metrics'];
    if (metrics is! Map) return const SizedBox.shrink();
    final topics = metrics['topics'] is Map
        ? Map<String, dynamic>.from(metrics['topics'])
        : <String, dynamic>{};
    final questions = metrics['questions'] is List
        ? List<Map<String, dynamic>>.from((metrics['questions'] as List)
            .map((item) => Map<String, dynamic>.from(item)))
        : <Map<String, dynamic>>[];
    questions.sort((a, b) {
      final missedA =
          ((a['total'] as num?) ?? 0) - ((a['correct'] as num?) ?? 0);
      final missedB =
          ((b['total'] as num?) ?? 0) - ((b['correct'] as num?) ?? 0);
      return missedB.compareTo(missedA);
    });
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SAVED RESULT EVIDENCE',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Based on ${_insights?['sample_count'] ?? 0} saved sheets · '
                'Average ${metrics['average_percentage'] ?? 0}%'),
            if (topics.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Topics',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...topics.entries.map((entry) {
                final counts =
                    entry.value is Map ? entry.value as Map : const {};
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '${entry.key}: ${counts['correct'] ?? 0}/${counts['total'] ?? 0} correct'),
                );
              }),
            ],
            if (questions.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Most missed questions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...questions
                  .where((q) =>
                      ((q['total'] as num?) ?? 0) >
                      ((q['correct'] as num?) ?? 0))
                  .take(8)
                  .map((q) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(q['question_text']?.toString() ??
                            'Question ${q['question_id'] ?? ''}'),
                        subtitle: Text(
                            '${q['correct'] ?? 0}/${q['total'] ?? 0} correct'
                            ' · ${q['topic_tag'] ?? 'Unspecified topic'}'),
                      )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _releaseResults() async {
    setState(() => _isReleasing = true);
    try {
      await ApiService.releaseResults(widget.examId);
      if (mounted) {
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text("Success"),
                  content: const Text(
                      "Results are now visible to all enrolled students."),
                  actions: [
                    TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        child: const Text("DONE"))
                  ],
                ));
      }
    } catch (e) {
      if (mounted) CheckMateUi.showTopPrompt(context, "Release failed: $e");
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }
}
