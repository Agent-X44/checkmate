import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'answer_sheet_design_screen.dart';
import 'exam_results_screen.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';
import '../services/pdf_generator.dart';
import '../services/exam_set_service.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../utils/ui_utils.dart';
import 'ai_questionnaire_screen.dart';
import 'student_insight_detail_screen.dart';

/// Manages the list of quizzes and exams within a course.
/// Enforces:
/// - BR-02: MCQ/TF support
/// - BR-03: Approval logic for instructors
/// - BR-11: Controlled release to students
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
  late Future<List<Map<String, dynamic>>> _examsFuture;
  List<Map<String, dynamic>>? _exams;
  String? _deletingExamId;

  final Map<String, bool> _sectionExpanded = {
    "Quizzes": true,
    "Exams": true,
    "Other Assessments": true,
  };

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  void _loadExams() {
    _examsFuture = SupabaseService.getExams(widget.courseId).then((exams) {
      if (mounted) setState(() => _exams = exams);
      return exams;
    });
  }

  Future<void> _refreshExams() async {
    final future = SupabaseService.getExams(widget.courseId);
    setState(() => _examsFuture = future);
    final exams = await future;
    if (mounted) setState(() => _exams = exams);
  }

  Future<void> _approveExam(String examId) async {
    try {
      await SupabaseService.approveExam(examId);
      await _refreshExams();
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Exam approved successfully!",
            isError: false);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Approval failed: $e");
      }
    }
  }

  Future<void> _unapproveExam(String examId) async {
    try {
      await ApiService.unapproveExam(examId);
      await _refreshExams();
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Exam reverted to Draft.",
            isError: false);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Failed to unapprove: $e");
      }
    }
  }

  Future<void> _releaseExamResults(String examId) async {
    try {
      await ApiService.releaseResults(examId);
      await _refreshExams();
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Results released!", isError: false);
      }
    } catch (e) {
      if (mounted) CheckMateUi.showTopPrompt(context, "Release failed: $e");
    }
  }

  Future<void> _generateSheets(String examId, String examTitle,
      {bool hasMultipleSets = false, String? templateId}) async {
    try {
      CheckMateUi.showTopPrompt(
        context,
        hasMultipleSets
            ? "Generating alternating Set A/B answer sheets..."
            : "Generating answer sheets...",
        isError: false,
      );

      // 1. Fetch questions to inspect template / total questions
      final questions = await SupabaseService.getExamQuestions(examId);
      final totalQuestions = questions.length;
      final mcqCount = questions
          .where((q) => (q['question_type'] ?? q['questionType']) == 'MCQ')
          .length;
      final tfCount = questions
          .where((q) => (q['question_type'] ?? q['questionType']) == 'TF')
          .length;

      // 2. Resolve template from AnswerSheetTemplateRegistry
      BubbleSheetTemplate? template;
      if (templateId != null && templateId.isNotEmpty) {
        template = AnswerSheetTemplateRegistry.byId(templateId);
      }
      template ??= AnswerSheetTemplateRegistry.forConfiguration(
          totalQuestions > 0 ? totalQuestions : 50, mcqCount, tfCount);

      // 3. Fetch enrolled students and generate database-linked QR identifiers
      final sheetData = await SupabaseService.generateAnswerSheetsData(
        examId,
        widget.courseId,
        alternateSets: hasMultipleSets,
      );

      if (sheetData.isEmpty) {
        if (mounted) {
          CheckMateUi.showTopPrompt(
            context,
            "No enrolled students were returned for this course.",
          );
        }
        return;
      }

      // 4. Trigger PDF Generator with the ACTUAL resolved template!
      await PdfGenerator.generateAndPrint(
        template,
        sheetData: sheetData,
      );
    } catch (e) {
      if (mounted) {
        final message = e.toString().contains('42501') ||
                e.toString().toLowerCase().contains('permission denied')
            ? "Supabase blocked answer-sheet creation. Apply backend/supabase_answer_sheets_policies.sql in the Supabase SQL Editor."
            : e.toString().toLowerCase().contains('set_type')
                ? "The answer-sheet database migration is missing. Run backend/supabase_answer_sheets_policies.sql in Supabase SQL Editor, then try again."
                : "PDF Generation failed: $e";
        CheckMateUi.showTopPrompt(context, message);
      }
    }
  }

  void _showEditQuestionDialog(
      Map<String, dynamic> q, Function(Map<String, dynamic>) onSave) {
    final textController =
        TextEditingController(text: q['question_text'] ?? '');
    final isTF = q['question_type'] == 'TF';

    // For MCQ, we need option controllers
    List<dynamic> options = q['options'] as List? ?? [];
    if (!isTF && options.length < 4) {
      options = List.from(options)
        ..addAll(List.generate(4 - options.length, (_) => ''));
    }

    final optionControllers = isTF
        ? <TextEditingController>[]
        : options
            .map((opt) => TextEditingController(text: opt.toString()))
            .toList();

    String currentAnswer =
        (q['correct_answer'] ?? 'A').toString().toUpperCase();

    showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(builder: (dialogContext, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : Colors.black;

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
              title: Text('Edit Question',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: 3,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Question Text',
                        border: const OutlineInputBorder(),
                        labelStyle:
                            TextStyle(color: textColor.withValues(alpha: 0.7)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!isTF) ...[
                      Text('Options:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: textColor)),
                      const SizedBox(height: 8),
                      ...List.generate(optionControllers.length, (i) {
                        final letter = String.fromCharCode(65 + i);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Text('$letter. ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textColor)),
                              Expanded(
                                child: TextField(
                                  controller: optionControllers[i],
                                  style: TextStyle(color: textColor),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    Text('Correct Answer:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: textColor)),
                    DropdownButton<String>(
                      value: currentAnswer,
                      dropdownColor:
                          isDark ? const Color(0xFF1E1E24) : Colors.white,
                      style: TextStyle(color: textColor),
                      items:
                          (isTF ? ['A', 'B'] : ['A', 'B', 'C', 'D']).map((ans) {
                        final label = isTF
                            ? (ans == 'A' ? 'A (True)' : 'B (False)')
                            : ans;
                        return DropdownMenuItem(value: ans, child: Text(label));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => currentAnswer = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('CANCEL',
                      style:
                          TextStyle(color: textColor.withValues(alpha: 0.7))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.yellow : Colors.blue),
                  onPressed: () async {
                    if (textController.text.trim().isEmpty) return;

                    final newOptions = isTF
                        ? ['True', 'False']
                        : optionControllers.map((c) => c.text.trim()).toList();

                    try {
                      CheckMateUi.showTopPrompt(context, "Saving...",
                          isError: false);
                      await ApiService.updateQuestion(
                        questionId: q['id'].toString(),
                        questionText: textController.text.trim(),
                        options: newOptions,
                        correctAnswer: currentAnswer,
                      );

                      // Update local state
                      final updatedQ = Map<String, dynamic>.from(q);
                      updatedQ['question_text'] = textController.text.trim();
                      updatedQ['options'] = newOptions;
                      updatedQ['correct_answer'] = currentAnswer;

                      onSave(updatedQ);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (mounted) {
                        CheckMateUi.showTopPrompt(context, "Question updated!",
                            isError: false);
                      }
                    } catch (e) {
                      if (mounted) {
                        CheckMateUi.showTopPrompt(
                            context, "Failed to update: $e");
                      }
                    }
                  },
                  child: Text('SAVE',
                      style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            );
          });
        });
  }

  Future<void> _reviewExam(String examId, String title) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final questions = await SupabaseService.getExamQuestions(examId);
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: questions.isEmpty
                        ? const Center(
                            child:
                                Text("No questions found for this assessment."))
                        : StatefulBuilder(builder: (context, setModalState) {
                            return ListView.builder(
                              controller: scrollController,
                              itemCount: questions.length,
                              itemBuilder: (context, index) {
                                final q = questions[index];
                                final isTF = q['question_type'] == 'TF';
                                final options = q['options'] as List? ?? [];

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                "${index + 1}. ${q['question_text'] ?? ''}",
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15),
                                              ),
                                            ),
                                            if (widget.isOwner)
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.edit_note,
                                                    color: Colors.orange),
                                                tooltip: "Edit Question",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () {
                                                  _showEditQuestionDialog(q,
                                                      (updatedQ) {
                                                    setModalState(() {
                                                      questions[index] =
                                                          updatedQ;
                                                    });
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (isTF) ...[
                                          const Text("A. True",
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                          const Text("B. False",
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                        ] else ...[
                                          ...List.generate(options.length, (i) {
                                            return Text(
                                                "${String.fromCharCode(65 + i)}. ${options[i]}",
                                                style: const TextStyle(
                                                    color: Colors.grey));
                                          }),
                                        ],
                                        const SizedBox(height: 8),
                                        Text(
                                          "Correct Answer: ${q['correct_answer']}",
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        CheckMateUi.showTopPrompt(context, "Failed to load questions: $e");
      }
    }
  }

  Future<void> _exportQuestionnaire(String examId, String title,
      {bool hasMultipleSets = false}) async {
    try {
      CheckMateUi.showTopPrompt(context, "Exporting questionnaire to DOCX...",
          isError: false);
      final questions = await SupabaseService.getExamQuestions(examId);
      if (questions.isEmpty) {
        if (mounted) {
          CheckMateUi.showTopPrompt(
              context, "No questions found for this assessment.");
        }
        return;
      }

      Directory? saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download');
        if (!await saveDir.exists()) {
          saveDir = await getExternalStorageDirectory();
        }
      } else {
        saveDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      if (hasMultipleSets) {
        // Clean title for file names
        final baseTitle = title.replaceAll(' (Sets A & B)', '');

        // Generate Set B
        final setBQuestions = ExamSetService.generateSetB(questions);

        // Export Set A
        final bytesSetA =
            await ApiService.exportToDocx("$baseTitle - Set A", questions);
        // Export Set B
        final bytesSetB =
            await ApiService.exportToDocx("$baseTitle - Set B", setBQuestions);

        final fileNameSetA =
            "CheckMate_${baseTitle.replaceAll(' ', '_')}_SetA_${DateTime.now().millisecondsSinceEpoch}.docx";
        final fileSetA = File('${saveDir?.path ?? ""}/$fileNameSetA');
        await fileSetA.writeAsBytes(bytesSetA);

        final fileNameSetB =
            "CheckMate_${baseTitle.replaceAll(' ', '_')}_SetB_${DateTime.now().millisecondsSinceEpoch}.docx";
        final fileSetB = File('${saveDir?.path ?? ""}/$fileNameSetB');
        await fileSetB.writeAsBytes(bytesSetB);

        if (mounted) {
          CheckMateUi.showTopPrompt(
              context, "Exported Set A and Set B to Downloads",
              isError: false);
        }
      } else {
        final bytes = await ApiService.exportToDocx(title, questions);
        final fileName =
            "CheckMate_${title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.docx";
        final file = File('${saveDir?.path ?? ""}/$fileName');
        await file.writeAsBytes(bytes);

        if (mounted) {
          CheckMateUi.showTopPrompt(
              context, "Exported & saved to Downloads: $fileName",
              isError: false);
        }
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Export failed: $e");
      }
    }
  }

  Future<void> _deleteExam(String examId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Assessment"),
        content: const Text(
            "Are you sure you want to delete this assessment? This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _deletingExamId = examId);
      try {
        await SupabaseService.deleteExam(examId);
        if (mounted) {
          final current = _exams;
          if (current != null) {
            setState(() {
              _exams = current.where((exam) => exam['id'] != examId).toList();
            });
          }
          CheckMateUi.showTopPrompt(context, "Assessment deleted successfully.",
              isError: false);
        }
      } catch (e) {
        if (mounted) {
          CheckMateUi.showTopPrompt(context, "Failed to delete assessment: $e");
        }
      } finally {
        if (mounted) setState(() => _deletingExamId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quizzes & Exams'),
        actions: [
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.design_services),
              tooltip: 'Dev Tools: Template Designer',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AnswerSheetDesignScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshExams,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _examsFuture,
          builder: (context, snapshot) {
            final exams = _exams ?? snapshot.data;
            if (exams == null &&
                snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final visibleExams = exams ?? const <Map<String, dynamic>>[];
            if (visibleExams.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * 0.2)
                        .clamp(24.0, 160.0),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        children: [
                          Icon(Icons.library_books_outlined,
                              size: 48, color: colors.primary),
                          const SizedBox(height: 16),
                          const Text("No assessments yet",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            widget.isOwner
                                ? "Tap + to create a quiz or exam."
                                : "Your instructor's assessments will appear here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSection(
                            context,
                            "Quizzes",
                            visibleExams
                                .where((e) =>
                                    (e['title'] ?? '').contains('[Quiz]'))
                                .toList()),
                        const SizedBox(height: 24),
                        _buildSection(
                            context,
                            "Exams",
                            visibleExams
                                .where((e) =>
                                    (e['title'] ?? '').contains('[Exam]'))
                                .toList()),
                        const SizedBox(height: 24),
                        _buildSection(
                            context,
                            "Other Assessments",
                            visibleExams
                                .where((e) =>
                                    !(e['title'] ?? '').contains('[Quiz]') &&
                                    !(e['title'] ?? '').contains('[Exam]'))
                                .toList()),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AIQuestionnaireScreen(
                      type: 'Assessment',
                      classId: widget.courseId,
                    ),
                  ),
                );
                if (result == true && mounted) {
                  await _refreshExams();
                }
              },
              backgroundColor: isDark ? colors.secondary : colors.primary,
              foregroundColor: isDark ? colors.onSecondary : colors.onPrimary,
              tooltip: 'Create assessment',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Map<String, dynamic> _getExamTemplateInfo(Map<String, dynamic> exam) {
    final bool isApproved = exam['is_approved'] == true;
    final String status = exam['status'] ?? 'Draft';
    final bool isDraft = !isApproved || status == 'Draft';

    final questions = exam['questions'] as List? ?? [];
    final templateId = exam['template_id']?.toString() ?? '';

    int totalItems = (exam['total_questions'] as num?)?.toInt() ?? 0;
    int mcqCount = (exam['mcq_count'] as num?)?.toInt() ?? 0;
    int tfCount = (exam['tf_count'] as num?)?.toInt() ?? 0;

    if (questions.isNotEmpty) {
      totalItems = questions.length;
      mcqCount = questions
          .where((q) => (q['question_type'] ?? q['questionType']) == 'MCQ')
          .length;
      tfCount = questions
          .where((q) => (q['question_type'] ?? q['questionType']) == 'TF')
          .length;
    }

    if (totalItems == 0 && templateId.isNotEmpty) {
      final t = AnswerSheetTemplateRegistry.byId(templateId);
      if (t != null) {
        totalItems = t.totalQuestions;
        mcqCount = t.mcqCount;
        tfCount = t.tfCount;
      }
    }

    // If it's a draft without generated items/questions, display clean pending status
    if (isDraft && totalItems <= 0) {
      return {
        'isDraftPending': true,
        'totalItems': 0,
        'mcqCount': 0,
        'tfCount': 0,
        'itemsDisplay': '-',
        'itemsSubtext': 'Draft',
        'templateName': '-',
        'templateSummary': 'Unassigned',
        'isMixed': false,
      };
    }

    BubbleSheetTemplate? template;
    if (templateId.isNotEmpty) {
      template = AnswerSheetTemplateRegistry.byId(templateId);
    }
    if (template == null && totalItems > 0) {
      template = AnswerSheetTemplateRegistry.forConfiguration(
          totalItems, mcqCount, tfCount);
    }
    template ??= AnswerSheetTemplateRegistry.byId('standard_50_questions') ??
        AnswerSheetTemplateRegistry.all.first;

    final isMixed = template.tfCount > 0 || tfCount > 0;

    String templateSummary = isMixed
        ? '${template.totalQuestions} Qs • Mixed (MCQ/TF)'
        : '${template.totalQuestions} Qs • Standard MCQ';

    return {
      'isDraftPending': false,
      'totalItems': totalItems,
      'mcqCount': mcqCount,
      'tfCount': tfCount,
      'itemsDisplay': '$totalItems Items',
      'itemsSubtext':
          isMixed ? '$mcqCount MCQ • $tfCount T/F' : '$mcqCount MCQ',
      'templateName': template.name,
      'templateSummary': templateSummary,
      'isMixed': isMixed,
    };
  }

  Widget _buildSection(
      BuildContext context, String title, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final actionColor = isDark ? colors.secondary : colors.primary;
    final isExpanded = _sectionExpanded[title] ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _sectionExpanded[title] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Text('${items.length}',
                    style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ...items.map((exam) {
            final isApproved = exam['is_approved'] == true;
            final isReleased = exam['results_released'] == true;

            // Clean title for display by removing tags
            String displayTitle = exam['title'] ?? 'Untitled';
            displayTitle = displayTitle
                .replaceAll('[Quiz]', '')
                .replaceAll('[Exam]', '')
                .trim();

            final hasMultipleSets = exam['has_multiple_sets'] == true;
            final info = _getExamTemplateInfo(exam);

            // Calculate analytics if available
            final answerSheets = exam['answer_sheets'] as List? ?? [];
            int submissions = 0;
            double totalPct = 0;
            for (final sheet in answerSheets) {
              final grades = sheet['grades'];
              if (grades != null) {
                submissions++;
                if (grades is List && grades.isNotEmpty) {
                  totalPct += (grades.first['percentage'] ?? 0.0);
                } else if (grades is Map) {
                  totalPct += (grades['percentage'] ?? 0.0);
                }
              }
            }
            final average = submissions > 0 ? totalPct / submissions : 0.0;

            final statusLabel =
                isReleased ? 'Released' : (isApproved ? 'Approved' : 'Draft');
            final statusBackground = isReleased
                ? colors.primary
                : isApproved
                    ? colors.secondary
                    : colors.surfaceContainerHighest;
            final statusForeground = isReleased
                ? colors.onPrimary
                : isApproved
                    ? colors.onSecondary
                    : colors.onSurfaceVariant;

            void openResults() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ExamResultsScreen(
                    examId: exam['id'],
                    examTitle: displayTitle,
                    classId: widget.courseId,
                    isOwner: widget.isOwner,
                  ),
                ),
              );
            }

            void openStudentResult() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentInsightDetailScreen(
                    examId: exam['id'],
                    examTitle: displayTitle,
                  ),
                ),
              );
            }

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: 40,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.secondary.withValues(alpha: isDark ? 0.16 : 0.28),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          title == 'Exams'
                              ? Icons.assignment_outlined
                              : Icons.quiz_outlined,
                          color: actionColor,
                        ),
                      ),
                      title: Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        info['isDraftPending'] == true
                            ? 'Questions pending'
                            : "${info['totalItems']} items • ${info['templateName']}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: widget.isOwner
                          ? PopupMenuButton<String>(
                              tooltip: 'More assessment actions',
                              icon: Icon(Icons.more_vert,
                                  color: colors.onSurfaceVariant),
                              onSelected: (action) {
                                switch (action) {
                                  case 'export':
                                    _exportQuestionnaire(
                                      exam['id'],
                                      displayTitle,
                                      hasMultipleSets: hasMultipleSets,
                                    );
                                    break;
                                  case 'print':
                                    _generateSheets(
                                      exam['id'],
                                      displayTitle,
                                      hasMultipleSets: hasMultipleSets,
                                      templateId: exam['template_id']?.toString(),
                                    );
                                    break;
                                  case 'unapprove':
                                    _unapproveExam(exam['id']);
                                    break;
                                  case 'delete':
                                    _deleteExam(exam['id']);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'export',
                                  child: Text('Export questionnaire'),
                                ),
                                const PopupMenuItem(
                                  value: 'print',
                                  child: Text('Print answer sheets'),
                                ),
                                if (isApproved && !isReleased)
                                  const PopupMenuItem(
                                    value: 'unapprove',
                                    child: Text('Return to draft'),
                                  ),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled: _deletingExamId != exam['id'],
                                  child: const Text('Delete assessment'),
                                ),
                              ],
                            )
                          : Icon(
                              isReleased
                                  ? Icons.chevron_right
                                  : Icons.lock_outline,
                              color: colors.onSurfaceVariant,
                            ),
                      onTap: widget.isOwner
                          ? openResults
                          : (isReleased ? openStudentResult : null),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusForeground,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasMultipleSets)
                          Text('Sets A & B',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant)),
                        if (submissions > 0)
                          Text(
                            '$submissions submitted • ${average.toStringAsFixed(1)}% avg',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (widget.isOwner) ...[
                      const Divider(height: 24),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _reviewExam(exam['id'], displayTitle),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('Review'),
                            style: TextButton.styleFrom(
                                foregroundColor: actionColor),
                          ),
                          TextButton.icon(
                            onPressed: openResults,
                            icon: const Icon(Icons.bar_chart_outlined, size: 18),
                            label: const Text('Results'),
                            style: TextButton.styleFrom(
                                foregroundColor: actionColor),
                          ),
                          if (!isApproved)
                            FilledButton.icon(
                              onPressed: () => _approveExam(exam['id']),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Approve'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.secondary,
                                foregroundColor: colors.onSecondary,
                              ),
                            )
                          else if (!isReleased)
                            FilledButton.icon(
                              onPressed: () =>
                                  _releaseExamResults(exam['id']),
                              icon: const Icon(Icons.publish_outlined, size: 18),
                              label: const Text('Release'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.secondary,
                                foregroundColor: colors.onSecondary,
                              ),
                            ),
                        ],
                      ),
                    ] else if (isReleased) ...[
                      const Divider(height: 24),
                      TextButton.icon(
                        onPressed: () =>
                            _reviewExam(exam['id'], displayTitle),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Review answers'),
                        style: TextButton.styleFrom(
                            foregroundColor: actionColor),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
