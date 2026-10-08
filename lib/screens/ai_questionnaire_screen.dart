import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/exam_set_service.dart';
import '../utils/ui_utils.dart';
import '../utils/choice_label.dart';
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
  int _currentStep = 0; // 0: Input, 1: Live questions, 2: Review
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

  // Only verified questions are shown while generation is in progress.
  String _generationStatus = 'Preparing your assessment...';
  String? _generationError;
  String _draftQuestionText = '';
  String _draftQuestionType = 'MCQ';
  final List<Map<String, dynamic>> _liveQuestions = [];
  final ScrollController _terminalScrollController = ScrollController();
  StreamSubscription? _streamSubscription;

  // Data Logic
  List<dynamic> _finalQuestions = [];
  bool _isGenerationFinished = false;
  PlatformFile? _selectedFile;
  String _sourceMode = 'topic';
  bool _hasMultipleSets = false;

  bool _savingDraft = false;
  bool _draftSaved = false;
  String? _draftId;

  Future<void> _saveToDraftsAuto() async {
    if (_savingDraft || _draftSaved) return;
    setState(() => _savingDraft = true);
    _draftId ??= const Uuid().v4();
    try {
      await SupabaseService.saveCreatedExam(
        classId: widget.classId,
        title: _inputController.text.isNotEmpty
            ? _inputController.text
            : (_selectedFile?.name ?? 'Generated Assessment'),
        assessmentType: _assessmentType,
        questions: _finalQuestions,
        hasMultipleSets: _hasMultipleSets,
        templateId: _selectedTemplate.id,
        draftId: _draftId,
      );
      if (mounted) setState(() => _draftSaved = true);
    } catch (e) {
      if (mounted) {
        debugPrint('Draft saving failed: $e');
        CheckMateUi.showTopPrompt(context,
            'Could not save your draft. Your questions are still here. Tap Retry save.');
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
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
    await _streamSubscription?.cancel();
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _currentStep = 1;
      _generationStatus = 'Preparing your assessment...';
      _generationError = null;
      _draftQuestionText = '';
      _liveQuestions.clear();
      _finalQuestions = [];
      _isGenerationFinished = false;
      _draftSaved = false;
      _draftId = null;
    });

    // The supplied items are only formatted in Existing Questions mode.
    if (mounted) {
      CheckMateUi.showTopPrompt(
        context,
        _sourceMode == 'existing_questions'
            ? 'Formatting your questions and supplied answer key. Review the draft before approval.'
            : 'Generation started. AI can make mistakes. Your assessment will be automatically saved to Drafts, where you can edit it later.',
        isError: false,
      );
    }

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

    _streamSubscription = stream.listen((event) async {
      if (!mounted) return;

      final type = event['type'];
      if (type == 'draft') {
        final draftText = (event['text'] ?? '').toString();
        if (draftText.isNotEmpty) {
          setState(() {
            _draftQuestionText = draftText;
            _draftQuestionType = (event['questionType'] ?? 'MCQ').toString();
            _generationStatus = 'Writing the next question...';
          });
        }
      } else if (type == 'question') {
        final question = event['question'];
        final number = event['number'];
        if (question is Map &&
            number is int &&
            number > 0 &&
            number <= _liveQuestions.length + 1) {
          setState(() {
            if (number == _liveQuestions.length + 1) {
              _liveQuestions.add(Map<String, dynamic>.from(question));
            } else {
              _liveQuestions[number - 1] = Map<String, dynamic>.from(question);
            }
            if (_draftQuestionText.trim() ==
                (question['questionText'] ?? '').toString().trim()) {
              _draftQuestionText = '';
            }
            _generationStatus = 'Building the remaining questions...';
          });
        }
        Timer(const Duration(milliseconds: 120), () {
          if (_terminalScrollController.hasClients) {
            _terminalScrollController.animateTo(
              _terminalScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else if (type == 'progress') {
        setState(() {
          final progress = (event['content'] ?? '').toString();
          _generationStatus = progress.startsWith('Checking')
              ? 'Preparing more questions'
              : progress;
          if (_generationStatus == 'Writing the next questions' ||
              _generationStatus == 'Preparing more questions') {
            _draftQuestionText = '';
          }
        });
      } else if (type == 'token') {
        // Older app builds display these as text. This screen uses verified
        // question events and only needs the initial preparation status.
        if (_liveQuestions.isEmpty &&
            (event['content'] ?? '').toString().startsWith('Preparing')) {
          setState(() => _generationStatus = 'Writing questions...');
        }
      } else if (type == 'complete') {
        final received = event['questions'];
        if (received is! List ||
            received.length != _selectedTotal ||
            received
                    .where((q) => q is Map && q['questionType'] == 'MCQ')
                    .length !=
                _selectedTemplate.mcqCount ||
            received
                    .where((q) => q is Map && q['questionType'] == 'TF')
                    .length !=
                _selectedTemplate.tfCount) {
          setState(() => _generationError =
              'Generated question counts do not match the selected answer sheet.');
          CheckMateUi.showTopPrompt(context,
              'Question types do not match the selected answer sheet.');
          return;
        }
        final ordered = <dynamic>[
          ...received.where((q) => q['questionType'] == 'MCQ'),
          ...received.where((q) => q['questionType'] == 'TF'),
        ];
        setState(() {
          _finalQuestions = ordered;
          _isGenerationFinished = true;
          _draftQuestionText = '';
          _generationStatus = _sourceMode == 'existing_questions'
              ? 'Questions formatted. Saving draft...'
              : 'All questions verified. Saving draft...';
        });

        // Automatically save to drafts securely using the frontend session
        await _saveToDraftsAuto();

        // Smooth transition to Review Step
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _currentStep = 2);
        });
      } else if (type == 'error') {
        setState(() => _generationError = event['content'].toString());
        CheckMateUi.showTopPrompt(
            context, 'Generation Failed: ${event['content']}');
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _generationError = e.toString());
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
    return PopScope(
      canPop: !_isGenerationFinished || _draftSaved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !mounted || _savingDraft) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Draft not saved'),
            content: const Text(
                'Retry saving or export your questions before leaving. Leave without saving?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep draft')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && mounted) {
          setState(() => _isGenerationFinished = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, false);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('AI ${widget.type} Builder')),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          layoutBuilder: (currentChild, previousChildren) =>
              currentChild ?? const SizedBox.shrink(),
          child: _currentStep == 0
              ? _buildInput()
              : _currentStep == 1
                  ? _buildTerminal()
                  : _buildReview(),
        ),
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
                      ? 'Paste questions with answer keys (e.g. Answer: B)...'
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
    final scheme = Theme.of(context).colorScheme;
    final drafted = _liveQuestions.length;
    return SafeArea(
      key: const ValueKey(1),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Building your assessment',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_generationStatus,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: _isGenerationFinished ? 1 : drafted / _selectedTotal,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.primary,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('$drafted of $_selectedTotal questions drafted',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${_selectedTemplate.mcqCount} MCQ${_selectedTemplate.tfCount > 0 ? '  ·  ${_selectedTemplate.tfCount} True/False' : ''}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_generationError != null) ...[
                  Text(_generationError!,
                      style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _startGeneration,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
                Expanded(
                  child: drafted == 0
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 42, color: scheme.primary),
                              const SizedBox(height: 12),
                              Text('Questions will appear here',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _terminalScrollController,
                          itemCount:
                              drafted + (_draftQuestionText.isNotEmpty ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == drafted) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: scheme.primary)),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Typing $_draftQuestionType draft...',
                                            style: TextStyle(
                                              color: scheme.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                          "${index + 1}. $_draftQuestionText █",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final question = _liveQuestions[index];
                            final type = question['questionType'];
                            final startsPart = index == 0 ||
                                _liveQuestions[index - 1]['questionType'] !=
                                    type;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (startsPart)
                                  _PartHeader(
                                    title: type == 'TF'
                                        ? 'PART 2: TRUE OR FALSE'
                                        : 'PART 1: MULTIPLE CHOICE',
                                  ),
                                _QuestionCard(
                                    data: question,
                                    index: index + 1,
                                    showAnswer: false),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
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
              ...part1.asMap().entries.map((entry) =>
                  _QuestionCard(data: entry.value, index: entry.key + 1)),
            ],
            if (part2.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _PartHeader(title: "PART 2: TRUE OR FALSE"),
              ...part2.asMap().entries.map((entry) => _QuestionCard(
                  data: entry.value, index: part1.length + entry.key + 1)),
            ],
            if (others.isNotEmpty) ...[
              if (part1.isNotEmpty || part2.isNotEmpty)
                const _PartHeader(title: "OTHER QUESTIONS"),
              ...others.asMap().entries.map((entry) => _QuestionCard(
                  data: entry.value,
                  index: part1.length + part2.length + entry.key + 1)),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _draftSaved
                          ? 'Saved to Drafts. Review the questions before approving the assessment.'
                          : _savingDraft
                              ? 'Saving your draft...'
                              : 'Your draft has not been saved. Retry saving before leaving this page.',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            if (!_draftSaved) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _savingDraft ? null : _saveToDraftsAuto,
                icon: const Icon(Icons.save_outlined),
                label: Text(_savingDraft ? 'Saving...' : 'Retry save'),
              ),
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
              onPressed: _draftSaved
                  ? () {
                      Navigator.pop(context, true);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.yellow
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : Colors.white,
              ),
              child: Text(
                  _draftSaved
                      ? 'RETURN TO CLASS (SAVED)'
                      : 'SAVE DRAFT TO CONTINUE',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
  final bool showAnswer;
  const _QuestionCard({
    required this.data,
    required this.index,
    this.showAnswer = true,
  });

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
                          color: showAnswer && isCorrect
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: showAnswer && isCorrect
                              ? Border.all(
                                  color: Colors.green.withValues(alpha: 0.5))
                              : null,
                        ),
                        child:
                            Text("$letter) ${stripChoiceLabel(options[i], i)}",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: showAnswer && isCorrect
                                      ? Colors.green.shade700
                                      : null,
                                  fontWeight: showAnswer && isCorrect
                                      ? FontWeight.bold
                                      : null,
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
