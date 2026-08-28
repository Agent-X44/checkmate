import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';

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
  final TextEditingController _inputController = TextEditingController(text: '');
  int _currentStep = 0; // 0: Input, 1: Terminal, 2: Review
  int _questionCount = 10;
  
  // Terminal Logic
  final List<String> _terminalLogs = [];
  final ScrollController _terminalScrollController = ScrollController();
  StreamSubscription? _streamSubscription;

  // Data Logic
  List<dynamic> _finalQuestions = [];
  bool _isGenerationFinished = false;

  void _startGeneration() async {
    if (_inputController.text.trim().isEmpty) return;
    
    // Hide keyboard safely
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    
    setState(() {
      _currentStep = 1;
      _terminalLogs.clear();
      _isGenerationFinished = false;
      _terminalLogs.add("[SYSTEM] Pipeline Initialization...");
    });

    // 1. Live Stream Listener (Debug Visuals)
    _streamSubscription = ApiService.generateExamStream(
      topic: _inputController.text,
      classId: widget.classId,
      questionCount: _questionCount,
    ).listen((event) {
      if (mounted) {
        setState(() => _terminalLogs.add(event));
        
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
      }
    }, onError: (e) {
      if (mounted) setState(() => _terminalLogs.add("[CRITICAL] Stream Error: $e"));
    });

    // 2. Data Fetcher (The actual JSON delivery)
    try {
      final data = await ApiService.createExam(
        topic: _inputController.text,
        classId: widget.classId,
        questionCount: _questionCount,
      );
      
      if (mounted) {
        setState(() {
          var questionsJson = data['questions'];
          if (questionsJson is List) {
            _finalQuestions = questionsJson;
          } else if (questionsJson is Map) {
            _finalQuestions = [questionsJson];
          }
          _isGenerationFinished = true;
          _terminalLogs.add("[SYSTEM] Data received. Cleaning up...");
          
          // Smooth transition to Review Step
          Future.delayed(const Duration(milliseconds: 1500), () {
             if (mounted) setState(() => _currentStep = 2);
          });
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint("[CRITICAL] UI Generation Failure: $e");
        CheckMateUi.showTopPrompt(context, 'Generation Failed: $e');
        setState(() => _currentStep = 0);
      }
    }
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
    return Padding(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Topic or Content Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _inputController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'e.g. OSPFv2 Routing, Chemistry...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(51),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Question Count', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('$_questionCount', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          Slider(
            value: _questionCount.toDouble(),
            min: 5, max: 50, divisions: 9,
            onChanged: (v) => setState(() => _questionCount = v.toInt()),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _startGeneration,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55)),
            child: const Text('GENERATE QUESTIONNAIRE'),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal() {
    return Container(
      key: const ValueKey(1),
      color: Colors.black,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text("LIVE AI ENGINE LOGS", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
            ],
          ),
          const Divider(color: Colors.greenAccent, height: 20),
          Expanded(
            child: ListView.builder(
              controller: _terminalScrollController,
              itemCount: _terminalLogs.length,
              itemBuilder: (context, index) {
                final log = _terminalLogs[index];
                final isAi = log.startsWith("AI:");
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: isAi ? Colors.white70 : Colors.greenAccent.withValues(alpha: 0.8),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (!_isGenerationFinished) 
            const LinearProgressIndicator(backgroundColor: Colors.white10, color: Colors.greenAccent)
          else
            const Text("COMPLETED", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> _exportDocx() async {
    try {
      final bytes = await ApiService.exportToDocx(
        "${widget.type} - ${_inputController.text}", 
        _finalQuestions
      );
      
      final dir = await getTemporaryDirectory(); // Use temp for sharing
      final fileName = "CheckMate_Assessment_${DateTime.now().millisecondsSinceEpoch}.docx";
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      
      if (mounted) {
        // Trigger Android Share Sheet (Allows "Save to device", "Send to Drive", etc.)
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Exported Assessment from CheckMate AI',
          ),
        );
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
    final others = _finalQuestions.where((q) => q['part'] != 1 && q['part'] != 2).toList();

    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      children: [
        if (part1.isNotEmpty) ...[
          const _PartHeader(title: "PART 1: MULTIPLE CHOICE"),
          ...part1.map((q) => _QuestionCard(data: q, index: _finalQuestions.indexOf(q) + 1)),
        ],
        if (part2.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _PartHeader(title: "PART 2: TRUE OR FALSE"),
          ...part2.map((q) => _QuestionCard(data: q, index: _finalQuestions.indexOf(q) + 1)),
        ],
        if (others.isNotEmpty) ...[
          if (part1.isNotEmpty || part2.isNotEmpty) const _PartHeader(title: "OTHER QUESTIONS"),
          ...others.map((q) => _QuestionCard(data: q, index: _finalQuestions.indexOf(q) + 1)),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _exportDocx,
          icon: const Icon(Icons.description),
          label: const Text('EXPORT TO DOCX'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55)),
          child: const Text('SAVE & FINALIZE'),
        ),
      ],
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
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent, letterSpacing: 1.2)),
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

    final rawAnswer = (data['correctAnswer'] ?? data['answer'] ?? "?").toString().toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$index. $text", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCorrect ? Colors.green.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isCorrect ? Border.all(color: Colors.green.withValues(alpha: 0.5)) : null,
                        ),
                        child: Text("$letter) ${options[i]}", 
                          style: TextStyle(
                            fontSize: 13, 
                            color: isCorrect ? Colors.green.shade700 : null,
                            fontWeight: isCorrect ? FontWeight.bold : null,
                          )
                        ),
                      ),
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
