import 'dart:async';
import 'package:flutter/material.dart';

import '../models/omr/processed_sheet.dart';
import '../services/sheet_evaluation_service.dart';
import '../utils/choice_label.dart';
import '../config/app_build.dart';

/// Read-only evaluation of the calibrated scan, saved automatically.
class SheetEvaluationScreen extends StatefulWidget {
  final ProcessedSheet sheet;
  final Map<String, dynamic> metadata;
  final Future<List<Map<String, dynamic>>> Function(String) loadQuestions;
  final Future<void> Function(ProcessedSheet) onEvaluated;
  final WidgetBuilder? developerToolsBuilder;

  const SheetEvaluationScreen({
    super.key,
    required this.sheet,
    required this.metadata,
    required this.loadQuestions,
    required this.onEvaluated,
    this.developerToolsBuilder,
  });

  @override
  State<SheetEvaluationScreen> createState() => _SheetEvaluationScreenState();
}

class _SheetEvaluationScreenState extends State<SheetEvaluationScreen> {
  late ProcessedSheet _currentSheet;
  ProcessedSheet? _evaluatedSheet;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentSheet = widget.sheet;
    unawaited(_evaluateAndSave());
  }

  Future<void> _evaluateAndSave() async {
    if (_isLoading || _isSaving || _saved) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_evaluatedSheet == null) {
        final examId = widget.metadata['exam_id']?.toString() ??
            widget.metadata['exams']?['id']?.toString() ??
            '';
        if (examId.isEmpty) {
          throw const FormatException(
              'The sheet did not resolve to an assessment.');
        }
        final questions = await widget.loadQuestions(examId);
        if (!mounted) return;
        _evaluatedSheet = SheetEvaluationService.evaluate(
            widget.sheet, questions,
            setType:
                (widget.metadata['set_type'] ?? widget.sheet.detectedSet ?? 'A')
                    .toString());
      }
      final evaluated = _evaluatedSheet!;
      setState(() {
        _currentSheet = evaluated;
        _isLoading = false;
        _isSaving = true;
      });
      // The callback must finish the durable local queue write before the page
      // reports success or allows navigation. Network sync runs separately.
      await widget.onEvaluated(evaluated);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException
              ? error.message.toString()
              : 'Could not save this evaluation. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSaving = false;
        });
      }
    }
  }

  String _choice(String? value, Map<String, dynamic> question) {
    if (value == null || value.isEmpty) return 'None';
    if (question['question_type'] == 'TF') {
      return value == 'A' ? 'True' : (value == 'B' ? 'False' : value);
    }
    final options = question['options'];
    final index = value.length == 1 ? value.codeUnitAt(0) - 65 : -1;
    if (options is List && index >= 0 && index < options.length) {
      return '$value. ${stripChoiceLabel(options[index], index)}';
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final studentName = widget.metadata['student_name'] ??
        widget.metadata['profiles']?['name'] ??
        'Student';
    final title =
        widget.metadata['exams']?['title'] ?? widget.sheet.templateName;
    final total = _currentSheet.results.length;
    final score =
        _currentSheet.results.where((r) => r.isCorrect == true).length;
    final flagged = _currentSheet.results.where((r) => r.isAmbiguous).length;

    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Evaluation Result'), actions: [
          if (AppBuild.developerTools && widget.developerToolsBuilder != null)
            IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Developer template tools',
                onPressed: _isLoading || _isSaving
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                            builder: widget.developerToolsBuilder!))),
        ]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(studentName.toString(),
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(title.toString()),
                      const SizedBox(height: 8),
                      if (!_isLoading && _evaluatedSheet != null)
                        Text('Score: $score / $total',
                            style: Theme.of(context).textTheme.titleMedium),
                      if (_saved) ...[
                        const SizedBox(height: 8),
                        const Text(
                            'Saved on this device. Syncs automatically.'),
                        const Text(
                            'Students can view results after instructor release.'),
                      ],
                      if (flagged > 0 && !_isLoading)
                        Text(
                            '$flagged ambiguous item(s) flagged and counted as incorrect.',
                            style: TextStyle(color: Colors.orange.shade800)),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading || _isSaving
                      ? Center(
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(_isSaving
                                ? 'Saving evaluation...'
                                : 'Verifying answer key...'),
                          ],
                        ))
                      : DefaultTabController(
                          length: 2,
                          child: Column(children: [
                            const TabBar(tabs: [
                              Tab(text: 'ITEMIZED RESULTS'),
                              Tab(text: 'CROPPED IMAGE'),
                            ]),
                            Expanded(
                                child: TabBarView(children: [
                              ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _currentSheet.questionDetails.length,
                                separatorBuilder: (_, index) => const Divider(),
                                itemBuilder: (context, index) {
                                  final result = _currentSheet.results[index];
                                  final question =
                                      _currentSheet.questionDetails[index];
                                  final marked = result.isAmbiguous
                                      ? (result.multipleAnswers.isEmpty
                                          ? 'Unclear mark'
                                          : result.multipleAnswers.join(', '))
                                      : _choice(result.answer, question);
                                  return ListTile(
                                    leading: Icon(
                                        result.isCorrect == true
                                            ? Icons.check_circle
                                            : Icons.cancel,
                                        color: result.isCorrect == true
                                            ? Colors.green
                                            : Colors.red),
                                    title: Text('Q${index + 1}: $marked'),
                                    subtitle: Text(
                                        'Correct answer: ${_choice(question['correct_answer']?.toString(), question)}'),
                                    trailing: Text(
                                        result.isCorrect == true ? '+1' : '0'),
                                  );
                                },
                              ),
                              InteractiveViewer(
                                  child: Image.memory(
                                _currentSheet.warpedImage,
                                fit: BoxFit.contain,
                                errorBuilder: (_, error, stack) =>
                                    const Text('Image preview unavailable.'),
                              )),
                            ])),
                          ]),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      if (_error != null)
                        TextButton.icon(
                          onPressed: _evaluateAndSave,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry evaluation'),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSaving || _isLoading
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(
                              _saved ? 'CONTINUE SCANNING' : 'RETAKE SHEET'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
