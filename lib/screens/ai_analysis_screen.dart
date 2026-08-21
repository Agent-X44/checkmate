import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/omr/processed_sheet.dart';
import 'session_insights_screen.dart';

/// Screen summarizing the current OMR scanning session.
/// Enforces BR-07: Instructor review before cloud synchronization.
class AIAnalysisScreen extends StatefulWidget {
  final List<ProcessedSheet> sheets;
  const AIAnalysisScreen({super.key, required this.sheets});

  @override
  State<AIAnalysisScreen> createState() => _AIAnalysisScreenState();
}

class _AIAnalysisScreenState extends State<AIAnalysisScreen> {
  bool _isSyncing = false;
  late List<ProcessedSheet> _results;

  @override
  void initState() {
    super.initState();
    _results = List.from(widget.sheets);
  }

  @override
  Widget build(BuildContext context) {
    // Audit current session for ambiguous marks needing human intervention
    int ambiguousCount = _results.where((s) => s.results.any((r) => r.isAmbiguous)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Session Summary"),
        actions: [
          if (ambiguousCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text("$ambiguousCount Flags", 
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final sheet = _results[index];
                final bool hasAmbiguity = sheet.results.any((r) => r.isAmbiguous);
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: hasAmbiguity ? Colors.orange : Colors.green,
                      child: Icon(hasAmbiguity ? Icons.warning : Icons.person, color: Colors.white),
                    ),
                    title: Text(sheet.qrData?.studentName ?? "Unknown Student"),
                    subtitle: Text("Score: ${ApiService.calculateScore(sheet).toStringAsFixed(1)}%"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Logic for individual sheet review could be added here
                    },
                  ),
                );
              },
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: _isSyncing ? null : _syncSession,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: _isSyncing 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("FINISH SESSION & SYNC", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  /// BR-07 & BR-08 Synchronization Gate.
  /// Maps local OMR results to backend batch schema.
  Future<void> _syncSession() async {
    if (_results.isEmpty) return;
    
    setState(() => _isSyncing = true);
    
    try {
      // Use the exam code from the first sheet in session
      final examId = _results.first.qrData?.examCode ?? "unknown";
      
      final batchData = _results.map((s) => {
        "sheet_id": s.qrData?.sheetIdentifier ?? "unknown",
        "student_id": s.qrData?.studentName ?? "unknown",
        "score": (ApiService.calculateScore(s) * s.results.length / 100).toInt(),
        "total": s.results.length,
        "answers": s.results.map((r) => r.toMap()).toList(),
      }).toList();

      // Enforce BR-08: Data must be persisted before analysis
      await ApiService.batchSyncResults(
        examId: examId,
        results: batchData,
      );

      if (mounted) {
        // Proceed to AI Insights (BR-09)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SessionInsightsScreen(examId: examId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync failed: $e"), backgroundColor: Colors.redAccent)
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
}
