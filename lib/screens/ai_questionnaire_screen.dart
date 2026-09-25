import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/exam_set_service.dart';
import '../utils/ui_utils.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';

class AIQuestionnaireScreen extends StatefulWidget {
  final String type;
  final String classId;

  const AIQuestionnaireScreen({
    super.key,
    required this.type,
    required this.classId,
  });

  @override
  State<AIQuestionnaireScreen> createState() => _AIQuestionnaireScreenState();
}

class _AIQuestionnaireScreenState extends State<AIQuestionnaireScreen> {
  final TextEditingController _inputController =
      TextEditingController(text: '');
  int _currentStep = 0; // 0: Input, 1: Terminal, 2: Review
  String _assessmentType = 'Quiz'; // Can be 'Quiz' or 'Exam'

  late int _selectedTotal;
  late BubbleSheetTemplate _selectedTemplate;

  Map<int, List<BubbleSheetTemplate>> get _templatesByTotal {
    final map = <int, List<BubbleSheetTemplate>>{};
    for (var t in AnswerSheetTemplateRegistry.all) {
      if (!map.containsKey(t.totalQuestions)) {
        map[t.totalQuestions] = [];
      }
      map[t.totalQuestions]!.add(t);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    final totals = _templatesByTotal.keys.toList()..sort();
    _selectedTotal = totals.contains(50) ? 50 : totals.first;
    _selectedTemplate = _templatesByTotal[_selectedTotal]!.firstWhere(
        (t) => t.tfCount == 0,
        orElse: () => _templatesByTotal[_selectedTotal]!.first);
  }

  // Terminal Logic
  String _streamedText = "";
  final ScrollController _terminalScrollController = ScrollController();
  StreamSubscription? _streamSubscription;

  // Data Logic
  List<dynamic> _finalQuestions = [];
  bool _isGenerationFinished = false;
  bool _isSaving = false;
  PlatformFile? _selectedFile;
  String _sourceMode = 'topic';
  bool _hasMultipleSets = false;

  Future<void> _saveToDrafts() async {
    setState(() => _isSaving = true);
    try {
      await SupabaseService.saveCreatedExam(
        classId: widget.classId,
        title: _inputController.text,
        assessmentType: _assessmentType,
        questions: _finalQuestions,
        hasMultipleSets: _hasMultipleSets,
        templateId: _selectedTemplate.id,
      );
      if (mounted) {
        CheckMateUi.showTopPrompt(
            context, '$_assessmentType saved to Drafts successfully!',
            isError: false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'Failed to save draft: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickSourceFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'pptx', 'doc', 'ppt'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.first;
          // Pre-fill topic from filename if empty
          if (_inputController.text.trim().isEmpty) {
            _inputController.text =
                _selectedFile!.name.split('.').first.replaceAll('_', ' ');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, 'File pick failed: $e');
      }
    }
  }

  void _startGeneration() async {
    if (_inputController.text.trim().isEmpty && _selectedFile == null) return;

    // Hide keyboard safely
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _currentStep = 1;
      _streamedText = "LOG: Initializing Pipeline...\n\n";
      _isGenerationFinished = false;
    });

    // Unified Stream: Handles both terminal logging and JSON delivery in one go
    final mcqCount = _selectedTemplate.mcqCount;
    final tfCount = _selectedTemplate.tfCount;
    final includeMcq = mcqCount > 0;
    final includeTf = tfCount > 0;

    // Choose the appropriate streaming API depending on whether a file was selected
    Stream<Map<String, dynamic>> stream;
    if (_selectedFile != null) {
      List<int> bytes = _selectedFile!.bytes ??
          (await File(_selectedFile!.path!).readAsBytes());
      if (!mounted) return;
      stream = ApiService.generateExamWithFile(
        topic: _inputController.text,
        classId: widget.classId,
        fileBytes: bytes,
        filename: _selectedFile!.name,
        questionCount: _selectedTotal,
        assessmentType: _assessmentType,
        includeMcq: includeMcq,
        includeTf: includeTf,
        mcqCount: mcqCount,
        tfCount: tfCount,
        sourceMode: _sourceMode,
        hasMultipleSets: _hasMultipleSets,
      );
    } else {
      stream = ApiService.generateExamStream(
        topic: _inputController.text,
        classId: widget.classId,
        questionCount: _selectedTotal,
        assessmentType: _assessmentType,
        includeMcq: includeMcq,
        includeTf: includeTf,
        mcqCount: mcqCount,
        tfCount: tfCount,
        sourceMode: _sourceMode,
        hasMultipleSets: _hasMultipleSets,
      );
    }

    _streamSubscription = stream.listen((event) {
      if (!mounted) return;

      final type = event['type'];
      if (type == 'token') {
        setState(() => _streamedText += (event['content'] ?? ''));

        // Auto-scroll to bottom of terminal
        Timer(const Duration(milliseconds: 100), () {
          if (_terminalScrollController.hasClients) {
            _terminalScrollController.animateTo(
              _terminalScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      } else if (type == 'complete') {
        setState(() {
          var questionsJson = event['questions'];
          if (questionsJson is List) {
            _finalQuestions = questionsJson;
          } else if (questionsJson is Map) {
            _finalQuestions = [questionsJson];
          }
          _isGenerationFinished = true;
          _streamedText +=
              "\n\n[SYSTEM] Assessment created and saved successfully! Transitioning...";
        });

        // Smooth transition to Review Step
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _currentStep = 2);
        });
      } else if (type == 'error') {
        setState(
            () => _streamedText += "\n[CRITICAL] Error: ${event['content']}");
        CheckMateUi.showTopPrompt(
            context, 'Generation Failed: ${event['content']}');
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _streamedText += "\n[CRITICAL] Stream Error: $e");
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _terminalScrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI ${widget.type} Builder')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _currentStep == 0
            ? _buildInput()
            : _currentStep == 1
                ? _buildTerminal()
                : _buildReview(),
      ),
    );
  }

  Widget _buildInput() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Question Source',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    ('topic', 'Topic', Icons.lightbulb_outline),
                    ('material', 'Material', Icons.menu_book),
                    (
                      'existing_questions',
                      'Existing Questions',
                      Icons.fact_check
                    ),
                  ])
                    ChoiceChip(
                      avatar: Icon(option.$3, size: 18),
                      label: Text(option.$2),
                      selected: _sourceMode == option.$1,
                      onSelected: (_) => setState(() {
                        _sourceMode = option.$1;
                        if (_sourceMode == 'topic') _selectedFile = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inputController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: _sourceMode == 'existing_questions'
                      ? 'Paste questions with optional answer keys...'
                      : 'e.g. OSPFv2 Routing, Chemistry...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha(51),
                ),
              ),
              if (_sourceMode != 'topic') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickSourceFile,
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          _selectedFile == null
                              ? (_sourceMode == 'existing_questions'
                                  ? 'Upload Questions File'
                                  : 'Upload Source File')
                              : _selectedFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_selectedFile != null) const SizedBox(width: 8),
                    if (_selectedFile != null)
                      TextButton(
                        onPressed: () => setState(() => _selectedFile = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              const Text('Assessment Type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    ('Quiz', Icons.flash_on),
                    ('Exam', Icons.assignment),
                  ])
                    ChoiceChip(
                      avatar: Icon(option.$2, size: 18),
                      label: Text(option.$1),
                      selected: _assessmentType == option.$1,
                      onSelected: (_) =>
                          setState(() => _assessmentType = option.$1),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Exam Variants',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.looks_one, size: 18),
                    label: const Text('Single Set'),
                    selected: !_hasMultipleSets,
                    onSelected: (_) => setState(() => _hasMultipleSets = false),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.style, size: 18),
                    label: const Text('Sets A & B'),
                    selected: _hasMultipleSets,
                    onSelected: (_) => setState(() => _hasMultipleSets = true),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Total Questions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final total in _templatesByTotal.keys)
                    ChoiceChip(
                      label: Text('$total Questions'),
                      selected: _selectedTotal == total,
                      onSelected: (_) => setState(() {
                        _selectedTotal = total;
                        _selectedTemplate =
                            _templatesByTotal[total]!.firstWhere(
                          (t) => t.tfCount == 0,
                          orElse: () => _templatesByTotal[total]!.first,
                        );
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Question Distribution',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ..._templatesByTotal[_selectedTotal]!.map((t) {
                final title = t.tfCount == 0
                    ? 'All Multiple Choice (${t.mcqCount} MCQ)'
                    : 'Mixed Format (${t.mcqCount} MCQ, ${t.tfCount} T/F)';
                final isSelected = _selectedTemplate == t;

                return Card(
                  elevation: 0,
                  color: isSelected
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.yellow.withValues(alpha: 0.1)
                          : Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withAlpha(100))
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: isSelected
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.yellow
                                  : Theme.of(context).colorScheme.primary)
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setState(() => _selectedTemplate = t),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RadioGroup<BubbleSheetTemplate>(
                        groupValue: _selectedTemplate,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedTemplate = val);
                          }
                        },
                        child: RadioListTile<BubbleSheetTemplate>(
                          title: Text(title,
                              style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          value: t,
                          activeColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.yellow
                                  : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  _startGeneration();
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.yellow
                          : Theme.of(context).colorScheme.primary,
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                ),
                child: const Text('GENERATE QUESTIONNAIRE',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    return Container(
      key: const ValueKey(1),
      color: Colors.black,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 10),
                  Text("LIVE AI ENGINE LOGS",
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2)),
                ],
              ),
              const Divider(color: Colors.greenAccent, height: 20),
              Expanded(
                child: SingleChildScrollView(
                  controller: _terminalScrollController,
                  child: Text(
                    _streamedText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!_isGenerationFinished)
                const LinearProgressIndicator(
                    backgroundColor: Colors.white10, color: Colors.greenAccent)
              else
                const Text("COMPLETED",
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDocx() async {
    try {
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

      final title = "${widget.type} - ${_inputController.text}";

      if (_hasMultipleSets) {
        final List<Map<String, dynamic>> questionsMap = _finalQuestions
            .map((q) => Map<String, dynamic>.from(q as Map))
            .toList();
        final setBQuestions = ExamSetService.generateSetB(questionsMap);
        final bytesSetA =
            await ApiService.exportToDocx("$title - Set A", _finalQuestions);
        final bytesSetB =
            await ApiService.exportToDocx("$title - Set B", setBQuestions);

        final fileNameA =
            "CheckMate_${_inputController.text.replaceAll(' ', '_')}_SetA_${DateTime.now().millisecondsSinceEpoch}.docx";
        final fileNameB =
            "CheckMate_${_inputController.text.replaceAll(' ', '_')}_SetB_${DateTime.now().millisecondsSinceEpoch}.docx";

        await File('${saveDir?.path ?? ""}/$fileNameA').writeAsBytes(bytesSetA);
        await File('${saveDir?.path ?? ""}/$fileNameB').writeAsBytes(bytesSetB);

        if (mounted) {
          CheckMateUi.showTopPrompt(
            context,
            "Exported Set A and Set B to Downloads",
            isError: false,
          );
        }
      } else {
        final bytes = await ApiService.exportToDocx(title, _finalQuestions);
        final fileName =
            "CheckMate_Assessment_${DateTime.now().millisecondsSinceEpoch}.docx";
        final file = File('${saveDir?.path ?? ""}/$fileName');
        await file.writeAsBytes(bytes);

        if (mounted) {
          CheckMateUi.showTopPrompt(
            context,
            "Exported & saved to Downloads: $fileName",
            isError: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CheckMateUi.showTopPrompt(context, "Export failed: $e");
      }
    }
  }

  Widget _buildReview() {
    final part1 = _finalQuestions.where((q) => q['part'] == 1).toList();
    final part2 = _finalQuestions.where((q) => q['part'] == 2).toList();
    final others =
        _finalQuestions.where((q) => q['part'] != 1 && q['part'] != 2).toList();

    return Center(
      key: const ValueKey(2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (part1.isNotEmpty) ...[
              const _PartHeader(title: "PART 1: MULTIPLE CHOICE"),
              ...part1.map((q) => _QuestionCard(
                  data: q, index: _finalQuestions.indexOf(q) + 1)),
            ],
            if (part2.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _PartHeader(title: "PART 2: TRUE OR FALSE"),
              ...part2.map((q) => _QuestionCard(
                  data: q, index: _finalQuestions.indexOf(q) + 1)),
            ],
            if (others.isNotEmpty) ...[
              if (part1.isNotEmpty || part2.isNotEmpty)
                const _PartHeader(title: "OTHER QUESTIONS"),
              ...others.map((q) => _QuestionCard(
                  data: q, index: _finalQuestions.indexOf(q) + 1)),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _exportDocx,
              icon: const Icon(Icons.description),
              label: const Text('EXPORT TO DOCX'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveToDrafts,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.yellow
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : Colors.white,
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white))
                  : const Text('FINISH & SAVE TO DRAFTS',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartHeader extends StatelessWidget {
  final String title;
  const _PartHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.yellow
                  : Colors.blueAccent,
              letterSpacing: 1.2)),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final dynamic data;
  final int index;
  const _QuestionCard({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    final text = data['questionText'] ?? data['text'] ?? "No question text";
    final isTF = data['questionType'] == 'TF' || data['part'] == 2;

    // Default options for T/F if the model is lazy
    List<dynamic> options = data['options'] as List? ?? [];
    if (options.isEmpty && isTF) {
      options = ["True", "False"];
    }

    final rawAnswer = (data['correctAnswer'] ?? data['answer'] ?? "?")
        .toString()
        .toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$index. $text",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...List.generate(options.length, (i) {
                final letter = String.fromCharCode(65 + i); // A, B...

                // Robust check for Correct Answer
                bool isCorrect = false;
                if (isTF) {
                  // Handle "A", "TRUE", or index 0
                  if (rawAnswer == "A" && i == 0) isCorrect = true;
                  if (rawAnswer == "B" && i == 1) isCorrect = true;
                  if (rawAnswer == "TRUE" && i == 0) isCorrect = true;
                  if (rawAnswer == "FALSE" && i == 1) isCorrect = true;
                } else {
                  if (rawAnswer == letter) isCorrect = true;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCorrect
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isCorrect
                              ? Border.all(
                                  color: Colors.green.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Text("$letter) ${options[i]}",
                            style: TextStyle(
                              fontSize: 13,
                              color: isCorrect ? Colors.green.shade700 : null,
                              fontWeight: isCorrect ? FontWeight.bold : null,
                            )),
                      )),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
