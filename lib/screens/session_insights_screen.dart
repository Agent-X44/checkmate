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
        });
      }
    } catch (e) {
      debugPrint("Initial load failed, retrying in 5s...");
      _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final data = await ApiService.analyzeClass(widget.examId);
        if (data.containsKey('insights') && data['insights'] != null) {
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
        ? Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text("Llama 3.1 is analyzing results...", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text("This happens in the background to prevent timeouts.", 
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInsightCard("PEDAGOGICAL INSIGHTS", _insights?['insights'] ?? "Analysis unavailable.", Icons.psychology),
                const SizedBox(height: 20),
                _buildInsightCard("TEACHING RECOMMENDATIONS", _insights?['recommendation'] ?? "Review flagged questions manually.", Icons.school),
                
                const SizedBox(height: 40),
                const Text("BR-11: CONTROLLED RELEASE", 
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _isReleasing ? null : _releaseResults,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: _isReleasing 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("RELEASE RESULTS TO STUDENTS", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildInsightCard(String title, String content, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.blueAccent, width: 0.5)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blueAccent),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
            const Divider(height: 30),
            Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
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
            content: const Text("Results are now visible to all enrolled students."),
            actions: [
              TextButton(onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
              }, child: const Text("DONE"))
            ],
          )
        );
      }
    } catch (e) {
      if (mounted) CheckMateUi.showTopPrompt(context, "Release failed: $e");
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }
}
