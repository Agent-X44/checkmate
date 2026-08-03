import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/omr/processed_sheet.dart';
import '../models/omr/templates/py_image_search_5.dart';
import '../services/cv/template_service.dart';
import '../services/cv/bubble_detection_service.dart';
import '../services/cv/threshold_service.dart';
import 'template_designer_screen.dart';

class AIAnalysisScreen extends StatefulWidget {
  final ProcessedSheet? processedSheet;
  const AIAnalysisScreen({super.key, this.processedSheet});

  @override
  State<AIAnalysisScreen> createState() => _AIAnalysisScreenState();
}

class _AIAnalysisScreenState extends State<AIAnalysisScreen> {
  int _phase = 0; // 0: Scanning/Evaluating, 1: Result
  bool _isDebugging = false;
  
  // Default Calibration (9:49 PM Config)
  double _yOffset = PyImageSearch5Template.calibratedYOffset.toDouble();
  double _xOffset = 0.0; 
  double _gridStart = PyImageSearch5Template.defaultGridStart;
  double _gridWidthRatio = PyImageSearch5Template.defaultGridWidth;

  List<Offset>? _customBubbles;

  late ProcessedSheet _currentSheet;

  @override
  void initState() {
    super.initState();
    if (widget.processedSheet != null) {
      _currentSheet = widget.processedSheet!;
    }
    _runEvaluation();
  }

  void _runEvaluation() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _phase = 1);
  }

  /// Re-processes the OMR results locally using current debug sliders.
  void _reprocessResults() {
    if (widget.processedSheet == null) return;

    try {
      final warpedMat = cv.imdecode(widget.processedSheet!.warpedImage, cv.IMREAD_COLOR);
      if (warpedMat.isEmpty) return;

      final thresholded = ThresholdService.applyAdaptiveThreshold(warpedMat);
      
      final template = PyImageSearch5Template();
      final answerAreaBinary = TemplateService.extractAnswerRegion(
        thresholded, 
        template,
        xOffset: _xOffset,
      );

      final List<cv.Mat> questionMats = TemplateService.splitQuestions(
        answerAreaBinary, 
        template,
        yOffset: _yOffset.toInt(),
      );

      final List<BubbleResult> newResults = [];
      final List<Uint8List> newQuestionImages = [];

      for (final m in questionMats) {
        final result = BubbleDetectionService.detectFilledBubble(
          m, 
          template.choicesPerQuestion, 
          isBinary: true,
          gridStart: _gridStart,
          gridWidthRatio: _gridWidthRatio,
          customXOffsets: _customBubbles?.map((p) => p.dx).toList(),
        );
        newResults.add(result);

        final bytes = Uint8List.fromList(cv.imencode(".jpg", m).$2);
        newQuestionImages.add(bytes);
        m.dispose();
      }

      setState(() {
        _currentSheet = ProcessedSheet(
          warpedImage: widget.processedSheet!.warpedImage,
          thresholdImage: widget.processedSheet!.thresholdImage,
          answerRegion: widget.processedSheet!.answerRegion,
          questionImages: newQuestionImages,
          results: newResults,
        );
      });

      warpedMat.dispose();
      thresholded.dispose();
      answerAreaBinary.dispose();
    } catch (e) {
      debugPrint("DEBUG REPROCESS ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluation Result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () {
              if (widget.processedSheet != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TemplateDesignerScreen(
                      imageBytes: widget.processedSheet!.warpedImage,
                      initialBubbles: _customBubbles,
                      onApply: (newBubbles) {
                        setState(() {
                          _customBubbles = newBubbles;
                        });
                        _reprocessResults();
                      },
                    ),
                  ),
                );
              }
            },
            tooltip: "Design Template",
          ),
          IconButton(
            icon: Icon(_isDebugging ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _isDebugging = !_isDebugging),
            tooltip: "Toggle Debug Sliders",
          )
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          if (_isDebugging) _buildDebugSliders(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _phase == 0 ? _buildProcessingUI() : _buildResultsUI(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugSliders() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blueGrey.withValues(alpha: 0.1),
      child: Column(
        children: [
          _debugSlider("Y-Offset", _yOffset, -50, 150, (v) {
            setState(() => _yOffset = v);
            _reprocessResults();
          }),
          _debugSlider("X-Offset", _xOffset, -0.2, 0.2, (v) {
            setState(() => _xOffset = v);
            _reprocessResults();
          }),
          _debugSlider("Grid Start", _gridStart, 0.0, 0.4, (v) {
            setState(() => _gridStart = v);
            _reprocessResults();
          }),
          _debugSlider("Grid Width", _gridWidthRatio, 0.5, 1.0, (v) {
            setState(() => _gridWidthRatio = v);
            _reprocessResults();
          }),
        ],
      ),
    );
  }

  Widget _debugSlider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: val,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(2), style: const TextStyle(fontSize: 10))),
      ],
    );
  }

  Widget _buildProcessingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(strokeWidth: 6),
          ),
          SizedBox(height: 32),
          Text(
            'Evaluating Bubbles...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text('Local OMR detection in progress'),
        ],
      ),
    );
  }

  Widget _buildResultsUI() {
    final sheet = _currentSheet;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWarpedPreview(sheet),
          const SizedBox(height: 24),
          const Text(
            'Detected Answers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildResultsList(sheet),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('FINISH SESSION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarpedPreview(ProcessedSheet sheet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Captured Paper (Tap to zoom)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showFullImage(context, sheet.warpedImage),
          child: Container(
            color: Colors.black,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(sheet.warpedImage, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }

  void _showFullImage(BuildContext context, dynamic imageBytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(imageBytes),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(ProcessedSheet sheet) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sheet.results.length,
      itemBuilder: (context, index) {
        final res = sheet.results[index];
        final bool hasAnswer = res.answer != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: hasAnswer ? Colors.yellowAccent : Colors.grey.shade200,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAnswer ? 'Answer: ${res.answer}' : 'No Answer Detected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: hasAnswer ? Colors.white : Colors.redAccent,
                    ),
                  ),
                  Text(
                    '${(res.confidence * 100).toInt()}% Conf.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    sheet.questionImages[index],
                    height: 80, 
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
