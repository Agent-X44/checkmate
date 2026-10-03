import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'answer_sheet_design_screen.dart';
import 'exam_results_screen.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';
import '../services/pdf_generator.dart';
import '../services/exam_set_service.dart';
import '../services/data_cache_service.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../utils/ui_utils.dart';
import '../utils/choice_label.dart';
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
    _initExamsWithCache();
  }

  Future<void> _initExamsWithCache() async {
    // 1. Instant cache retrieval for seamless UX
    final cached = await DataCacheService.getExams(widget.courseId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _exams = cached;
      });
    }

    // 2. Fetch fresh network data and update cache
    await _refreshExams();
  }

  Future<void> _refreshExams() async {
    final future = SupabaseService.getExams(widget.courseId);
    setState(() => _examsFuture = future);
    try {
      final exams = await future;
      await DataCacheService.saveExams(widget.courseId, exams);
      if (mounted) setState(() => _exams = exams);
    } catch (e) {
      debugPrint("Error loading exams: $e");
    }
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
        hasMultipleSets: hasMultipleSets,
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
        : options.asMap().entries
            .map((entry) => TextEditingController(
                text: stripChoiceLabel(entry.value, entry.key)))
            .toList();

    String currentAnswer =
        (q['correct_answer'] ?? 'A').toString().toUpperCase();

    showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(builder: (dialogContext, setDialogState) {
            final theme = Theme.of(dialogContext);
            final colors = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            final actionColor = isDark ? colors.secondary : colors.primary;
            final onActionColor =
                isDark ? colors.onSecondary : colors.onPrimary;
            final textColor = colors.onSurface;

            return AlertDialog(
              backgroundColor: colors.surface,
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
                        labelStyle: TextStyle(color: colors.onSurfaceVariant),
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
                      dropdownColor: colors.surface,
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
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: onActionColor,
                  ),
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
                  child: const Text('SAVE',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          });
        });
  }

  Future<void> _reviewExam(String examId, String title) async {
    final theme = Theme.of(context);
    final reviewAccent = theme.brightness == Brightness.dark
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<Map<String, dynamic>> items = [];
      bool isStudentResult = false;
      String emptyMessage = 'No questions found for this assessment.';
      
      if (widget.isOwner) {
        items = await SupabaseService.getExamQuestions(examId);
      } else {
        final result = await SupabaseService.getMyResult(examId);
        final rawAnswers = result?['grade']?['answers'];
        isStudentResult = true;
        if (result == null) {
          emptyMessage = 'Your result is not available or has not been released yet.';
        } else if (rawAnswers is List && rawAnswers.isNotEmpty) {
          items = rawAnswers
              .whereType<Map>()
              .map((answer) => Map<String, dynamic>.from(answer))
              .toList();
        } else {
          emptyMessage = 'This result has no saved item answers to review.';
        }
      }

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
                    child: items.isEmpty
                        ? Center(child: Text(emptyMessage, textAlign: TextAlign.center))
                        : StatefulBuilder(builder: (context, setModalState) {
                            return ListView.builder(
                              controller: scrollController,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final q = items[index];
                                final isTF = q['question_type'] == 'TF';
                                final options = q['options'] as List? ?? [];
                                
                                if (isStudentResult) {
                                  // Display student answer and evaluation
                                  final qNum = q['question_number'] ?? (index + 1);
                                  final qText = q['question_text']?.toString() ?? '';
                                  final isCorrect = q['isCorrect'] == true;
                                  final isAmbiguous = q['isAmbiguous'] == true;
                                  final answer = q['answer']?.toString();
                                  final correctAnswer = q['correct_answer']?.toString() ?? '';
                                  
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
                                    final marks = q['multipleAnswers'] is List
                                        ? (q['multipleAnswers'] as List).join(', ')
                                        : 'Multiple';
                                    studentAnsText = 'Student answer: $marks';
                                  } else if (answer == null || answer.isEmpty) {
                                    studentAnsText = 'Student answer: None';
                                  } else if (isTF) {
                                    final tfLabel = answer == 'A' ? 'True' : (answer == 'B' ? 'False' : answer);
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
                                  if (isTF) {
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
                                          if (correctAnsText.isNotEmpty) ...[
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
                                                icon: Icon(Icons.edit_note,
                                                    color: reviewAccent),
                                                tooltip: "Edit Question",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () {
                                                  _showEditQuestionDialog(q,
                                                      (updatedQ) {
                                                    setModalState(() {
                                                      items[index] =
                                                          updatedQ;
                                                    });
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (isTF) ...[
                                          Text("A. True",
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                          Text("B. False",
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                        ] else ...[
                                          ...List.generate(options.length, (i) {
                                            return Text(
                                                "${String.fromCharCode(65 + i)}. ${stripChoiceLabel(options[i], i)}",
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant));
                                          }),
                                        ],
                                        const SizedBox(height: 8),
                                        Text(
                                          "Correct Answer: ${q['correct_answer']}",
                                          style: TextStyle(
                                              color: reviewAccent,
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
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
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
            final updated =
                current.where((exam) => exam['id'] != examId).toList();
            setState(() {
              _exams = updated;
            });
            await DataCacheService.saveExams(widget.courseId, updated);
          }
          if (mounted) {
            CheckMateUi.showTopPrompt(
                context, "Assessment deleted successfully.",
                isError: false);
          }
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
                    builder: (context) => AnswerSheetDesignScreen(
                      courseId: widget.courseId,
                    ),
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

            final visibleExams = (exams ?? const <Map<String, dynamic>>[])
                .where((exam) => widget.isOwner || exam['is_approved'] == true)
                .toList();

            int getStatusWeight(Map<String, dynamic> exam) {
              if (exam['results_released'] == true) return 3;
              if (exam['is_approved'] == true) return 2;
              return 1; // Draft
            }

            int getTypeWeight(Map<String, dynamic> exam) {
              final title = exam['title'] ?? '';
              if (title.contains('[Exam]')) return 1;
              return 2; // Quiz
            }

            visibleExams.sort((a, b) {
              // 1. Sort by Status (Drafts -> Approved -> Released)
              final statusA = getStatusWeight(a);
              final statusB = getStatusWeight(b);
              if (statusA != statusB) {
                return statusA.compareTo(statusB);
              }

              // 2. Sort by Type (Exams -> Quizzes -> Other)
              final typeA = getTypeWeight(a);
              final typeB = getTypeWeight(b);
              if (typeA != typeB) {
                return typeA.compareTo(typeB);
              }

              // 3. Sort by Date Created (Newest first)
              final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
              final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
              return dateB.compareTo(dateA);
            });

            String getStatusGroup(Map<String, dynamic> exam) {
              if (exam['results_released'] == true) return 'Released';
              if (exam['is_approved'] == true) return 'Approved';
              return 'Draft';
            }

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
                              size: 48,
                              color:
                                  isDark ? colors.secondary : colors.primary),
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
                        if (visibleExams.any((e) => getStatusGroup(e) == 'Draft')) ...[
                          _buildSection(
                              context,
                              "Drafts",
                              visibleExams
                                  .where((e) => getStatusGroup(e) == 'Draft')
                                  .toList()),
                          const SizedBox(height: 24),
                        ],
                        if (visibleExams.any((e) => getStatusGroup(e) == 'Approved')) ...[
                          _buildSection(
                              context,
                              "Approved",
                              visibleExams
                                  .where((e) => getStatusGroup(e) == 'Approved')
                                  .toList()),
                          const SizedBox(height: 24),
                        ],
                        if (visibleExams.any((e) => getStatusGroup(e) == 'Released')) ...[
                          _buildSection(
                              context,
                              "Released",
                              visibleExams
                                  .where((e) => getStatusGroup(e) == 'Released')
                                  .toList()),
                          const SizedBox(height: 24),
                        ],
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

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'Unknown date';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return 'Unknown date';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
    final onActionColor = isDark ? colors.onSecondary : colors.onPrimary;
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

            final isExam = (exam['title'] ?? '').contains('[Exam]');
            final examType = isExam ? 'Exam' : 'Quiz';
            
            final itemColor = isExam
                ? colors.tertiary
                : actionColor;

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
                ? actionColor
                : isApproved
                    ? actionColor
                    : colors.surfaceContainerHighest;
            final statusForeground = isReleased
                ? onActionColor
                : isApproved
                    ? onActionColor
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
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: widget.isOwner
                    ? openResults
                    : (isReleased ? openStudentResult : null),
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
                            color: itemColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isExam
                                ? Icons.assignment_outlined
                                : Icons.quiz_outlined,
                            color: itemColor,
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: itemColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: itemColor.withValues(alpha: 0.2)),
                                  ),
                                  child: Text(
                                    examType,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: itemColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(exam['created_at']?.toString()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              info['isDraftPending'] == true
                                  ? 'Questions pending'
                                  : "${info['totalItems']} items • ${info['templateName']}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
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
                                        templateId:
                                            exam['template_id']?.toString(),
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
                            icon:
                                const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('Review'),
                            style: TextButton.styleFrom(
                                foregroundColor: actionColor),
                          ),
                          TextButton.icon(
                            onPressed: openResults,
                            icon:
                                const Icon(Icons.bar_chart_outlined, size: 18),
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
                                backgroundColor: actionColor,
                                foregroundColor: onActionColor,
                              ),
                            )
                          else if (!isReleased)
                            FilledButton.icon(
                              onPressed: () => _releaseExamResults(exam['id']),
                              icon:
                                  const Icon(Icons.publish_outlined, size: 18),
                              label: const Text('Release'),
                              style: FilledButton.styleFrom(
                                backgroundColor: actionColor,
                                foregroundColor: onActionColor,
                              ),
                            ),
                        ],
                      ),
                    ] else if (isReleased) ...[
                      const Divider(height: 24),
                      TextButton.icon(
                        onPressed: () => _reviewExam(exam['id'], displayTitle),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Review answers'),
                        style:
                            TextButton.styleFrom(foregroundColor: actionColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
