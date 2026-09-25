import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';
import '../models/omr/processed_sheet.dart';
import 'session_insights_screen.dart';
import 'sheet_evaluation_screen.dart';

/// Screen summarizing the current OMR scanning session.
/// Enforces:
/// - BR-07: Instructor review before cloud synchronization.
/// - BR-08: Batch synchronization.
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
    int ambiguousCount =
        _results.where((s) => s.results.any((r) => r.isAmbiguous)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Session Summary"),
        actions: [
          if (ambiguousCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text("$ambiguousCount Flags",
                    style: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No scanned sheets in this session yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final sheet = _results[index];
                      final bool hasAmbiguity =
                          sheet.results.any((r) => r.isAmbiguous);

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    hasAmbiguity ? Colors.orange : Colors.green,
                                child: Icon(
                                    hasAmbiguity ? Icons.warning : Icons.person,
                                    color: Colors.white),
                              ),
                              title: Text(sheet.qrData?.studentName ??
                                  "Unknown Student"),
                              subtitle: Text(
                                  "Score: ${ApiService.calculateScore(sheet).toStringAsFixed(1)}%"),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final updated =
                                    await Navigator.push<ProcessedSheet>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SheetEvaluationScreen(
                                      sheet: sheet,
                                      metadata: {
                                        'student_name':
                                            sheet.qrData?.studentName,
                                        'set_type': sheet.detectedSet,
                                        'exams': {
                                          'title': sheet.templateName,
                                          'id': sheet.qrData?.examCode,
                                        },
                                      },
                                    ),
                                  ),
                                );
                                if (updated != null && mounted) {
                                  setState(() {
                                    _results[index] = updated;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 768),
                child: ElevatedButton(
                  onPressed:
                      _isSyncing || _results.isEmpty ? null : _syncSession,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: _isSyncing
                      ? CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary)
                      : const Text("FINISH SESSION & SYNC",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )),
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

      final batchData = _results
          .map((s) => {
                "sheet_id": s.qrData?.sheetIdentifier ?? "unknown",
                "student_id": s.qrData?.studentName ?? "unknown",
                "score": (ApiService.calculateScore(s) * s.results.length / 100)
                    .toInt(),
                "total": s.results.length,
                "answers": s.results.map((r) => r.toMap()).toList(),
              })
          .toList();

      // Enforce BR-08: Data must be persisted before analysis
      await ApiService.batchSyncResults(
        examId: examId,
        results: batchData,
      );

      if (mounted) {
        // Proceed to AI Insights (BR-09)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => SessionInsightsScreen(examId: examId)),
        );
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Sync failed: $e");
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
}
