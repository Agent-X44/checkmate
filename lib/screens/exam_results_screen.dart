import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';
import 'session_insights_screen.dart';
import 'student_insight_detail_screen.dart';

/// Screen for instructors to view class-wide assessment results,
/// individual student scores, and trigger AI analysis or release grades.
class ExamResultsScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final String classId;
  final bool isOwner;

  const ExamResultsScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.classId,
    required this.isOwner,
  });

  @override
  State<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends State<ExamResultsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _studentResults = [];
  Map<String, dynamic>? _examData;
  double _avgScore = 0.0;
  double _highestScore = 0.0;
  double _lowestScore = 100.0;
  int _totalSubmissions = 0;
  bool _isReleasing = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadExamResults();
  }

  Future<void> _loadExamResults() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch exam metadata
      final examRes = await SupabaseService.client
          .from('exams')
          .select('*, classes(name)')
          .eq('id', widget.examId)
          .maybeSingle();

      _examData = examRes;

      // 2. Fetch this exam's graded sheets under the signed-in user's RLS policies.
      final sheets = await ApiService.getExamResults(widget.examId);

      final List<Map<String, dynamic>> list = [];
      double sumPct = 0;
      double maxPct = 0;
      double minPct = 100;
      int count = 0;

      for (final item in sheets) {
        final sheetId = item['id']?.toString();
        final profile = item['profiles'];
        final grades = item['grades'];

        Map<String, dynamic>? gradeData;
        if (grades is List && grades.isNotEmpty) {
          gradeData = Map<String, dynamic>.from(grades.first);
        } else if (grades is Map) {
          gradeData = Map<String, dynamic>.from(grades);
        }

        if (gradeData != null) {
          count++;
          final pct = (gradeData['percentage'] as num?)?.toDouble() ?? 0.0;
          sumPct += pct;
          if (pct > maxPct) maxPct = pct;
          if (pct < minPct) minPct = pct;

          list.add({
            'sheet_id': sheetId,
            'set_type': item['set_type'] ?? 'A',
            'student_id': item['student_id'],
            'student_name': profile?['name'] ??
                profile?['email']?.split('@')[0] ??
                'Student',
            'score': gradeData['score'] ?? 0,
            'total': gradeData['total_questions'] ?? 0,
            'percentage': pct,
          });
        }
      }

      // Sort students alphabetically by name
      list.sort((a, b) => (a['student_name'] as String)
          .toLowerCase()
          .compareTo((b['student_name'] as String).toLowerCase()));

      if (mounted) {
        setState(() {
          _studentResults = list;
          _totalSubmissions = count;
          _avgScore = count > 0 ? (sumPct / count) : 0.0;
          _highestScore = count > 0 ? maxPct : 0.0;
          _lowestScore = count > 0 ? minPct : 0.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading exam results: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        CheckMateUi.showTopPrompt(
            context, "Could not load results. Please try refreshing.");
      }
    }
  }

  Future<void> _releaseResults() async {
    if (_isReleasing) {
      return;
    }
    final withdrawing = _examData?['results_released'] == true;
    if (withdrawing) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Unrelease results?'),
                content: const Text(
                    'Students will lose access to these results. Saved grades and insights will be kept.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Unrelease'))
                ],
              ));
      if (confirm != true || !mounted) {
        return;
      }
    }
    setState(() => _isReleasing = true);
    try {
      if (withdrawing) {
        await ApiService.unreleaseResults(widget.examId);
      } else {
        await ApiService.releaseResults(widget.examId);
      }
      if (mounted) {
        setState(() {
          _examData = {...?_examData, 'results_released': !withdrawing};
        });
      }
      if (mounted) {
        CheckMateUi.showTopPrompt(
            context,
            withdrawing
                ? "Results unreleased."
                : "Results released to students!",
            isError: false);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(
            context, "Could not update result access: $e");
      }
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }

  Future<void> _exportScores() async {
    if (_isExporting) {
      return;
    }
    setState(() => _isExporting = true);
    try {
      final bytes = await ApiService.exportScoresXlsx(widget.examId);
      final safeTitle = widget.examTitle
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final shortTitle = safeTitle.length > 60
          ? safeTitle.substring(0, 60)
          : (safeTitle.isEmpty ? 'Assessment' : safeTitle);
      final name = 'CheckMate_${shortTitle}_Scores.xlsx';
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save assessment scores',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (savedPath != null && mounted) {
        CheckMateUi.showTopPrompt(context, 'Scores exported to $name',
            isError: false);
      }
    } catch (error) {
      debugPrint('Score export failed: $error');
      if (mounted) {
        CheckMateUi.showTopPrompt(
            context, 'Could not export scores. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellowAccent : Colors.blueAccent;

    final bool isReleased = _examData?['results_released'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology, color: Colors.purpleAccent),
            tooltip: "AI Class Analysis",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SessionInsightsScreen(examId: widget.examId),
                ),
              ).then((_) {
                if (mounted) _loadExamResults();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExamResults,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Analytics Summary Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _statTile("Submissions", "$_totalSubmissions",
                                  Icons.people, isDark),
                              _statTile(
                                  "Class Average",
                                  "${_avgScore.toStringAsFixed(1)}%",
                                  Icons.analytics,
                                  isDark),
                              _statTile("Highest", "${_highestScore.toInt()}%",
                                  Icons.arrow_upward, isDark),
                              _statTile("Lowest", "${_lowestScore.toInt()}%",
                                  Icons.arrow_downward, isDark),
                            ],
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final analysisButton = OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SessionInsightsScreen(
                                              examId: widget.examId),
                                    ),
                                  ).then((_) {
                                    if (mounted) _loadExamResults();
                                  });
                                },
                                icon: const Icon(Icons.auto_awesome),
                                label: const Text("VIEW AI CLASS ANALYSIS",
                                    textAlign: TextAlign.center),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accentColor,
                                ),
                              );
                              final releaseButton = ElevatedButton.icon(
                                onPressed:
                                    _isReleasing ? null : _releaseResults,
                                icon: _isReleasing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Icon(isReleased
                                        ? Icons.unpublished_outlined
                                        : Icons.publish),
                                label:
                                    Text(isReleased ? "UNRELEASE" : "RELEASE"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentColor,
                                  foregroundColor:
                                      isDark ? Colors.black : Colors.white,
                                ),
                              );
                              final exportButton = OutlinedButton.icon(
                                onPressed:
                                    _isExporting || _totalSubmissions == 0
                                        ? null
                                        : _exportScores,
                                icon: _isExporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.table_view_outlined),
                                label: const Text('EXPORT SCORES (.XLSX)'),
                              );
                              final showRelease = widget.isOwner &&
                                  (isReleased ||
                                      _examData?['is_approved'] == true);
                              if (constraints.maxWidth < 780) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    analysisButton,
                                    if (widget.isOwner) ...[
                                      const SizedBox(height: 8),
                                      exportButton,
                                    ],
                                    if (showRelease) ...[
                                      const SizedBox(height: 8),
                                      releaseButton,
                                    ],
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: analysisButton),
                                  if (widget.isOwner) ...[
                                    const SizedBox(width: 8),
                                    Expanded(child: exportButton),
                                  ],
                                  if (showRelease) ...[
                                    const SizedBox(width: 8),
                                    releaseButton,
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Student Results List
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadExamResults,
                    child: _studentResults.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                    "No scanned results found for this assessment yet.\nSwipe down to refresh.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            ],
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: constraints.maxWidth > 992
                                    ? (constraints.maxWidth - 960) / 2
                                    : 16,
                                vertical: 16,
                              ),
                              itemCount: _studentResults.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _studentResults[index];
                                final pct =
                                    (item['percentage'] as num).toDouble();
                                final isPassed = pct >= 60.0;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isPassed
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.red.withValues(alpha: 0.2),
                                    child: Text(
                                      "${item['set_type']}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isPassed
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item['student_name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                      "Score: ${item['score']} / ${item['total']} • Set ${item['set_type']}"),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${pct.toStringAsFixed(1)}%",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isPassed
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            StudentInsightDetailScreen(
                                          examId: widget.examId,
                                          studentId:
                                              item['student_id']?.toString(),
                                          sheetId: item['sheet_id']?.toString(),
                                          examTitle:
                                              "${item['student_name']} - ${widget.examTitle}",
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, bool isDark) {
    return SizedBox(
      width: 112,
      child: Column(
        children: [
          Icon(icon,
              size: 18,
              color: isDark ? Colors.yellowAccent : Colors.blueAccent),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
