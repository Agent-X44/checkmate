import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../services/api_service.dart';
import '../models/omr/processed_sheet.dart';
import '../models/omr/templates/standard_50_questions.dart';
import '../services/image_processor.dart';
import '../services/cv/template_service.dart';
import '../services/cv/bubble_detection_service.dart';
import '../services/cv/threshold_service.dart';
import 'template_designer_screen.dart';

class AIAnalysisScreen extends StatefulWidget {
  final ProcessedSheet? processedSheet;
  final Uint8List? rawImage;
  final List<double>? rawCorners;

  const AIAnalysisScreen({
    super.key,
    this.processedSheet,
    this.rawImage,
    this.rawCorners,
  });

  @override
  State<AIAnalysisScreen> createState() => _AIAnalysisScreenState();
}

class _AIAnalysisScreenState extends State<AIAnalysisScreen> {
  int _phase = 0; // 0: Evaluating, 1: Result
  bool _isDebugging = false;

  double _yOffset = 0;
  double _gridStart = Standard50QuestionsTemplate.defaultGridStart;
  double _gridWidthRatio = Standard50QuestionsTemplate.defaultGridWidth;
  double _bubbleThreshold = Standard50QuestionsTemplate.defaultThreshold;
  double _stripHeightMultiplier =
      Standard50QuestionsTemplate.defaultStripHeight;
  double _gridYSpace = Standard50QuestionsTemplate.defaultGridYSpace;
  double _xOffset = Standard50QuestionsTemplate.calibratedXOffset.toDouble();
  double _setGridStart = 0.1;
  double _setGridWidth = 0.8;
  double _setGridYPos = 0.5;
  double _setZoneWidth = 0.45;
  double _setZoneHeight = 0.60;

  late Rect _col1;
  late Rect _col2;
  Rect? _customQr;
  Rect? _customSet;
  List<Offset> _customBubbles = [];
  List<Offset> _setBubbles = [];

  ProcessedSheet? _currentSheet;
  Isolate? _isolate;
  final ReceivePort _receivePort = ReceivePort();

  @override
  void initState() {
    super.initState();
    final defaultTemplate = Standard50QuestionsTemplate();
    _col1 = defaultTemplate.answerRegions[0];
    _col2 = defaultTemplate.answerRegions[1];
    _customQr = defaultTemplate.qrRegion;
    _customSet = defaultTemplate.setRegion ??
        const Rect.fromLTRB(0.18, 0.15, 0.35, 0.22);
    _setBubbles = defaultTemplate.setBubbles ?? [];

    if (widget.processedSheet != null) {
      _currentSheet = widget.processedSheet!;
      _phase = 1;
    } else if (widget.rawImage != null && widget.rawCorners != null) {
      _startBackgroundProcessing();
    }
  }

  @override
  void dispose() {
    _isolate?.kill();
    _receivePort.close();
    super.dispose();
  }

  Future<void> _startBackgroundProcessing() async {
    _isolate = await Isolate.spawn(
        ImageProcessor.edgeDetectionWorker, _receivePort.sendPort);
    _receivePort.listen((message) {
      if (message is SendPort) {
        message.send(OmrRequest(
          bytes: widget.rawImage!,
          corners: widget.rawCorners!,
          template: Standard50QuestionsTemplate(),
          replyPort: _receivePort.sendPort,
          stripHeightMultiplier: _stripHeightMultiplier,
          customSetRegion: _customSet,
          customSetBubbles: _setBubbles,
        ));
      } else if (message is ProcessedSheet && mounted) {
        setState(() {
          _currentSheet = message;
          _phase = 1;
        });
      }
    });
  }

  void _reprocessResults() {
    if (_currentSheet == null || !mounted) return;
    try {
      final warpedMat =
          cv.imdecode(_currentSheet!.warpedImage, cv.IMREAD_COLOR);
      if (warpedMat.isEmpty) return;
      final thresholded = ThresholdService.applyOtsuThreshold(warpedMat);
      final template = Standard50QuestionsTemplate();
      final List<BubbleResult> results = [];
      final List<Uint8List> images = [];

      // 1. Set Detection
      String? detectedSet;
      if (_setBubbles.isNotEmpty) {
        final List<double> fills = [];
        for (var p in _setBubbles) {
          final int x = (p.dx * thresholded.width).toInt();
          final int y = (p.dy * thresholded.height).toInt();
          const int sz = 25;
          final r = cv.Rect((x - sz ~/ 2).clamp(0, thresholded.width - sz),
              (y - sz ~/ 2).clamp(0, thresholded.height - sz), sz, sz);
          final bubbleMat = thresholded.region(r);
          fills.add(cv.countNonZero(bubbleMat) / (sz * sz));
          bubbleMat.dispose();
        }
        if (fills.isNotEmpty) {
          int winner = 0;
          for (int i = 1; i < fills.length; i++) {
            if (fills[i] > fills[winner]) {
              winner = i;
            }
          }
          if (fills[winner] > _bubbleThreshold) {
            detectedSet = "SET ${String.fromCharCode(65 + winner)}";
          }
        }
      } else if (_customSet != null) {
        final setMat = TemplateService.extractRegion(thresholded, _customSet!);
        final res = BubbleDetectionService.detectFilledBubble(setMat, 2,
            isBinary: true,
            gridStart: _setGridStart,
            gridWidthRatio: _setGridWidth,
            zoneWidthRatio: _setZoneWidth,
            zoneHeightRatio: _setZoneHeight,
            threshold: _bubbleThreshold);
        if (res.answer != null) detectedSet = "SET ${res.answer}";
        setMat.dispose();
      }

      // 2. Column Grid Processing
      final regions = [_col1, _col2];
      final qPerRegion = (template.totalQuestions / 2).ceil();
      for (int i = 0; i < 2; i++) {
        final regionMat =
            TemplateService.extractRegion(thresholded, regions[i]);
        final count =
            (i == 1) ? template.totalQuestions - qPerRegion : qPerRegion;
        final qMats = TemplateService.splitQuestions(
          regionMat,
          count,
          yOffset: _yOffset.toInt(),
          heightMultiplier: _stripHeightMultiplier,
          ySpace: _gridYSpace,
        );
        for (final m in qMats) {
          results.add(BubbleDetectionService.detectFilledBubble(
            m,
            4,
            isBinary: true,
            gridStart: _gridStart,
            gridWidthRatio: _gridWidthRatio,
            threshold: _bubbleThreshold,
          ));
          images.add(Uint8List.fromList(cv.imencode(".jpg", m).$2));
          m.dispose();
        }
        regionMat.dispose();
      }

      // 3. Custom Manually Added Bubbles (Points)
      for (var p in _customBubbles) {
        final int x =
            ((p.dx + (_xOffset / thresholded.width)) * thresholded.width)
                .toInt();
        final int y =
            ((p.dy + (_yOffset / thresholded.height)) * thresholded.height)
                .toInt();
        const int areaSize = 30;
        final rect = cv.Rect(
            (x - areaSize ~/ 2).clamp(0, thresholded.width - areaSize),
            (y - areaSize ~/ 2).clamp(0, thresholded.height - areaSize),
            areaSize,
            areaSize);
        final bubbleMat = thresholded.region(rect);
        final double fillRatio =
            cv.countNonZero(bubbleMat) / (areaSize * areaSize);
        final bool isFilled = fillRatio > _bubbleThreshold;

        results.add(BubbleResult(
            answer: isFilled ? "MANUAL" : null,
            confidence: 1.0,
            isFilled: isFilled));
        images.add(Uint8List.fromList(cv.imencode(".jpg", bubbleMat).$2));
        bubbleMat.dispose();
      }

      setState(() {
        _currentSheet = ProcessedSheet(
          warpedImage: _currentSheet!.warpedImage,
          thresholdImage: _currentSheet!.thresholdImage,
          answerRegion: _currentSheet!.answerRegion,
          questionImages: images,
          results: results,
          qrData: _currentSheet!.qrData,
          detectedSet: detectedSet,
          templateName: template.name,
        );
      });
      warpedMat.dispose();
      thresholded.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluation Result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () {
              if (_currentSheet != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TemplateDesignerScreen(
                      imageBytes: _currentSheet!.warpedImage,
                      initialAnswerRegions: [_col1, _col2],
                      initialQrRegion: _customQr,
                      initialSetRegion: _customSet,
                      initialSetBubbles: _setBubbles,
                      initialBubbles: _customBubbles,
                      onApply:
                          (newBubbles, newBoxes, newQr, newSet, newSetBubbles) {
                        setState(() {
                          if (newBoxes.length >= 2) {
                            _col1 = newBoxes[0];
                            _col2 = newBoxes[1];
                          }
                          _customQr = newQr;
                          _customSet = newSet;
                          _setBubbles = newSetBubbles;
                          _customBubbles = newBubbles;
                        });
                        _reprocessResults();
                      },
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: Icon(
                _isDebugging ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _isDebugging = !_isDebugging),
          )
        ],
      ),
      body: Center(
        child: Container(
          constraints:
              BoxConstraints(maxWidth: isTablet ? 900 : double.infinity),
          child: Column(
            children: [
              if (_isDebugging) _buildDebugSliders(),
              Expanded(
                  child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _phase == 0
                          ? _buildProcessingUI()
                          : _buildResultsUI())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugSliders() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("QUICK ALIGNMENT",
              style: TextStyle(
                  color: Colors.yellowAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          SizedBox(
            height: 220,
            child: ListView(
              children: [
                _debugSlider("Col1 X", _col1.left, 0.0, 1.0, (v) {
                  setState(() => _col1 =
                      Rect.fromLTWH(v, _col1.top, _col1.width, _col1.height));
                  _reprocessResults();
                }),
                _debugSlider("Col1 Y", _col1.top, 0.0, 1.0, (v) {
                  setState(() => _col1 =
                      Rect.fromLTWH(_col1.left, v, _col1.width, _col1.height));
                  _reprocessResults();
                }),
                _debugSlider("Col2 X", _col2.left, 0.0, 1.0, (v) {
                  setState(() => _col2 =
                      Rect.fromLTWH(v, _col2.top, _col2.width, _col2.height));
                  _reprocessResults();
                }),
                _debugSlider("Col2 Y", _col2.top, 0.0, 1.0, (v) {
                  setState(() => _col2 =
                      Rect.fromLTWH(_col2.left, v, _col2.width, _col2.height));
                  _reprocessResults();
                }),
                _debugSlider("Y-Offset", _yOffset, -50.0, 50.0, (v) {
                  setState(() => _yOffset = v);
                  _reprocessResults();
                }),
                const Divider(color: Colors.white24),
                _sectionHeader("EXAM SET ALIGNMENT"),
                _debugSlider("Set X", _customSet?.left ?? 0, 0.0, 1.0, (v) {
                  setState(() => _customSet = Rect.fromLTWH(
                      v,
                      _customSet?.top ?? 0,
                      _customSet?.width ?? 0.1,
                      _customSet?.height ?? 0.05));
                  _reprocessResults();
                }),
                _debugSlider("Set Y", _customSet?.top ?? 0, 0.0, 1.0, (v) {
                  setState(() => _customSet = Rect.fromLTWH(
                      _customSet?.left ?? 0,
                      v,
                      _customSet?.width ?? 0.1,
                      _customSet?.height ?? 0.05));
                  _reprocessResults();
                }),
                _debugSlider("Set W", _customSet?.width ?? 0, 0.01, 0.5, (v) {
                  setState(() => _customSet = Rect.fromLTWH(
                      _customSet?.left ?? 0,
                      _customSet?.top ?? 0,
                      v,
                      _customSet?.height ?? 0.05));
                  _reprocessResults();
                }),
                _debugSlider("Set H", _customSet?.height ?? 0, 0.01, 0.5, (v) {
                  setState(() => _customSet = Rect.fromLTWH(
                      _customSet?.left ?? 0,
                      _customSet?.top ?? 0,
                      _customSet?.width ?? 0.1,
                      v));
                  _reprocessResults();
                }),
                _debugSlider("Set G-Start", _setGridStart, 0.0, 0.5, (v) {
                  setState(() => _setGridStart = v);
                  _reprocessResults();
                }),
                _debugSlider("Set G-Width", _setGridWidth, 0.5, 1.0, (v) {
                  setState(() => _setGridWidth = v);
                  _reprocessResults();
                }),
                _debugSlider("Set G-YPos", _setGridYPos, 0.0, 1.0, (v) {
                  setState(() => _setGridYPos = v);
                  _reprocessResults();
                }),
                _debugSlider("Set Z-Width", _setZoneWidth, 0.1, 1.0, (v) {
                  setState(() => _setZoneWidth = v);
                  _reprocessResults();
                }),
                _debugSlider("Set Z-Height", _setZoneHeight, 0.1, 1.0, (v) {
                  setState(() => _setZoneHeight = v);
                  _reprocessResults();
                }),
                const Divider(color: Colors.white24),
                _sectionHeader("OMR GRID SETTINGS"),
                _debugSlider("Grid Space", _gridStart, 0.0, 0.5, (v) {
                  setState(() => _gridStart = v);
                  _reprocessResults();
                }),
                _debugSlider("Grid Size", _gridWidthRatio, 0.5, 1.0, (v) {
                  setState(() => _gridWidthRatio = v);
                  _reprocessResults();
                }),
                _debugSlider("Threshold", _bubbleThreshold, 0.05, 0.5, (v) {
                  setState(() => _bubbleThreshold = v);
                  _reprocessResults();
                }),
                _debugSlider("Strip Height", _stripHeightMultiplier, 0.5, 2.5,
                    (v) {
                  setState(() => _stripHeightMultiplier = v);
                  _reprocessResults();
                }),
                _debugSlider("Grid Y-Space", _gridYSpace, -5.0, 5.0, (v) {
                  setState(() => _gridYSpace = v);
                  _reprocessResults();
                }),
                _debugSlider("X-Offset", _xOffset, -50.0, 50.0, (v) {
                  setState(() => _xOffset = v);
                  _reprocessResults();
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0, top: 2.0),
      child: Text(title,
          style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _debugSlider(String label, double val, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.white))),
        Expanded(
            child: Slider(
                value: val.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                activeColor: Colors.yellowAccent)),
        SizedBox(
            width: 40,
            child: Text(val.toStringAsFixed(3),
                style:
                    const TextStyle(fontSize: 9, color: Colors.yellowAccent))),
      ],
    );
  }

  Widget _buildProcessingUI() {
    return const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(strokeWidth: 6),
      SizedBox(height: 24),
      Text('Processing Paper...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildResultsUI() {
    final sheet = _currentSheet;
    if (sheet == null) return const Center(child: Text('No data'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sheet.qrData != null) _buildStudentInfo(sheet.qrData!),
        _buildInteractivePreview(sheet),
        const SizedBox(height: 20),
        const Text('DETECTION RESULTS',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 10),
        if (sheet.detectedSet != null) _buildSetResultTile(sheet.detectedSet!),
        ...List.generate(
            sheet.results.length, (i) => _buildResultTile(sheet, i)),
        const SizedBox(height: 40),
        ElevatedButton(
            onPressed: () async {
              if (_currentSheet != null) {
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  await ApiService.submitGradedSheet(
                    studentId: _currentSheet!.qrData?.studentName ?? 'unknown',
                    courseId: _currentSheet!.qrData?.examCode ?? 'unknown',
                    sheet: _currentSheet!,
                  );
                  if (mounted) {
                    Navigator.pop(context); // Pop loading
                    Navigator.pop(context); // Pop screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Results synced successfully!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context); // Pop loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync failed: $e')),
                    );
                  }
                }
              } else {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55)),
            child: const Text('FINISH SESSION')),
      ],
    );
  }

  Widget _buildInteractivePreview(ProcessedSheet sheet) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxWidth / 0.707);
      return Stack(children: [
        Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
              color: Colors.black, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Image.memory(sheet.warpedImage, fit: BoxFit.fill),
            if (_isDebugging)
              Positioned.fill(
                  child: CustomPaint(
                      painter: BoxAlignmentPainter(
                regions: [_col1, _col2],
                setRegion: _customSet,
                setBubbles: _setBubbles,
                gridStart: _gridStart,
                gridWidthRatio: _gridWidthRatio,
                setGridStart: _setGridStart,
                setGridWidth: _setGridWidth,
                setGridYPos: _setGridYPos,
                setZoneWidth: _setZoneWidth,
                setZoneHeight: _setZoneHeight,
                yOffset: _yOffset,
                xOffset: _xOffset,
                stripHeight: _stripHeightMultiplier,
                gridYSpace: _gridYSpace,
              ))),
          ]),
        ),
      ]);
    });
  }

  Widget _buildStudentInfo(dynamic qr) {
    final sheet = _currentSheet;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor =
        isDarkMode ? Colors.yellowAccent : Colors.blueAccent;
    final Color qrTextColor = isDarkMode ? Colors.white : Colors.black87;

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: accentColor.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accentColor.withValues(alpha: 0.2))),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text(qr.studentName,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold))),
                        if (sheet?.detectedSet != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(sheet!.detectedSet!,
                                style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    Text("${qr.examTitle} • ${qr.examCode}",
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    Divider(height: 24, color: accentColor),
                    Row(
                      children: [
                        Icon(Icons.qr_code_scanner,
                            size: 16, color: accentColor),
                        const SizedBox(width: 8),
                        Text("QR CONTENT:",
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: accentColor)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            qr.toString(),
                            style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: qrTextColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ])),
        ),
      ],
    );
  }

  Widget _buildSetResultTile(String setLabel) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor =
        isDarkMode ? Colors.yellowAccent : Colors.blueAccent;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: accentColor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accentColor, width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accentColor,
          child: Icon(Icons.assignment_turned_in,
              color: isDarkMode ? Colors.black : Colors.white, size: 20),
        ),
        title: Text(
          "EXAM SET DETECTED",
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: accentColor,
              letterSpacing: 1.1),
        ),
        subtitle: Text(
          setLabel,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
          onPressed: () => _showSetOverrideDialog(),
          tooltip: "Override Set",
        ),
      ),
    );
  }

  void _showSetOverrideDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Override Exam Set"),
        content: const Text("Manually select the correct set for this sheet:"),
        actions: [
          TextButton(
            onPressed: () {
              _updateDetectedSet("SET A");
              Navigator.pop(context);
            },
            child: const Text("SET A"),
          ),
          TextButton(
            onPressed: () {
              _updateDetectedSet("SET B");
              Navigator.pop(context);
            },
            child: const Text("SET B"),
          ),
        ],
      ),
    );
  }

  void _updateDetectedSet(String newSet) {
    if (_currentSheet == null) return;
    final template = Standard50QuestionsTemplate();
    setState(() {
      _currentSheet = ProcessedSheet(
        warpedImage: _currentSheet!.warpedImage,
        thresholdImage: _currentSheet!.thresholdImage,
        answerRegion: _currentSheet!.answerRegion,
        questionImages: _currentSheet!.questionImages,
        results: _currentSheet!.results,
        qrData: _currentSheet!.qrData,
        detectedSet: newSet,
        templateName: _currentSheet!.templateName.isNotEmpty
            ? _currentSheet!.templateName
            : template.name,
      );
    });
  }

  Widget _buildResultTile(ProcessedSheet sheet, int i) {
    final res = sheet.results[i];
    final bool isAmbiguous = res.isAmbiguous;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isAmbiguous ? 4 : 0,
      shadowColor: isAmbiguous ? Colors.orange : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isAmbiguous ? Colors.orange : Colors.transparent, width: 2),
      ),
      child: ListTile(
        onTap: isAmbiguous ? () => _showAmbiguityDialog(i) : null,
        leading: CircleAvatar(
            radius: 14,
            backgroundColor: isAmbiguous
                ? Colors.orange
                : (res.answer != null
                    ? Colors.green
                    : Colors.red.withValues(alpha: 0.1)),
            child: Text("${i + 1}",
                style: const TextStyle(fontSize: 10, color: Colors.white))),
        title: Row(
          children: [
            Text(res.answer ?? (isAmbiguous ? "MULTIPLE ANSWERS" : "MISSING"),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isAmbiguous
                        ? Colors.orange
                        : (res.answer == null ? Colors.red : null))),
            if (isAmbiguous) ...[
              const SizedBox(width: 8),
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 18),
            ]
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(sheet.questionImages[i],
                    height: 40, fit: BoxFit.fitHeight)),
            if (isAmbiguous)
              Text("Detected: ${res.multipleAnswers.join(', ')}",
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${(res.confidence * 100).toInt()}%",
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            if (isAmbiguous)
              const Text("TAP TO FIX",
                  style: TextStyle(
                      fontSize: 8,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showAmbiguityDialog(int index) {
    if (_currentSheet == null) return;
    final res = _currentSheet!.results[index];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Resolve Question ${index + 1}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Multiple answers detected. Please select the intended answer:"),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_currentSheet!.questionImages[index]),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                ...res.multipleAnswers.map((ans) => ChoiceChip(
                      label: Text(ans),
                      selected: false,
                      onSelected: (_) {
                        _resolveAmbiguity(index, ans);
                        Navigator.pop(context);
                      },
                    )),
                ActionChip(
                  avatar: const Icon(Icons.close, size: 16),
                  label: const Text("Invalid"),
                  onPressed: () {
                    _resolveAmbiguity(index, null);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _resolveAmbiguity(int index, String? chosenAnswer) {
    if (_currentSheet == null) return;
    final template = Standard50QuestionsTemplate();
    setState(() {
      final updatedResults = List<BubbleResult>.from(_currentSheet!.results);
      final oldRes = updatedResults[index];

      updatedResults[index] = oldRes.copyWith(
        answer: chosenAnswer,
        isAmbiguous: false, // Marking as resolved
      );

      _currentSheet = ProcessedSheet(
        warpedImage: _currentSheet!.warpedImage,
        thresholdImage: _currentSheet!.thresholdImage,
        answerRegion: _currentSheet!.answerRegion,
        questionImages: _currentSheet!.questionImages,
        results: updatedResults,
        qrData: _currentSheet!.qrData,
        templateName: _currentSheet!.templateName.isNotEmpty
            ? _currentSheet!.templateName
            : template.name,
        detectedSet: _currentSheet!.detectedSet,
      );
    });
  }
}

class BoxAlignmentPainter extends CustomPainter {
  final List<Rect> regions;
  final Rect? setRegion;
  final List<Offset> setBubbles;
  final double gridStart;
  final double gridWidthRatio;
  final double setGridStart;
  final double setGridWidth;
  final double setGridYPos;
  final double setZoneWidth;
  final double setZoneHeight;
  final double yOffset;
  final double xOffset;
  final double stripHeight;
  final double gridYSpace;

  BoxAlignmentPainter({
    required this.regions,
    this.setRegion,
    this.setBubbles = const [],
    required this.gridStart,
    required this.gridWidthRatio,
    this.setGridStart = 0.1,
    this.setGridWidth = 0.8,
    this.setGridYPos = 0.5,
    this.setZoneWidth = 0.45,
    this.setZoneHeight = 0.60,
    required this.yOffset,
    this.xOffset = 0.0,
    required this.stripHeight,
    this.gridYSpace = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final gridPaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final stripPaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    final setPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var r in regions) {
      final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height,
          r.right * size.width, r.bottom * size.height);
      canvas.drawRect(rect, paint);
      final colW = rect.width;
      final bStart = rect.left + (colW * gridStart) + xOffset;
      final bWidth = colW * gridWidthRatio;
      final cellW = bWidth / 4;
      for (int i = 0; i <= 4; i++) {
        final x = bStart + (i * cellW);
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      }
      const int qCount = 25;
      final rowStep = rect.height / qCount;
      for (int i = 0; i < qCount; i++) {
        final cY =
            rect.top + ((i + 0.5) * rowStep) + yOffset + (i * gridYSpace);
        final h = rowStep * stripHeight;
        final t = cY - (h / 2);
        final b = cY + (h / 2);
        if (b > rect.top && t < rect.bottom) {
          final sRect = Rect.fromLTRB(rect.left, math.max(rect.top, t),
              rect.right, math.min(rect.bottom, b));
          canvas.drawRect(sRect, stripPaint);
          canvas.drawRect(sRect, gridPaint);
        }
      }
    }

    if (setRegion != null) {
      final r = Rect.fromLTRB(
          setRegion!.left * size.width,
          setRegion!.top * size.height,
          setRegion!.right * size.width,
          setRegion!.bottom * size.height);
      canvas.drawRect(r, setPaint);

      final sStart = r.left + (r.width * setGridStart);
      final sWidth = r.width * setGridWidth;
      final cW = sWidth / 2;

      // Draw detection zones for Set A and B
      for (int i = 0; i < 2; i++) {
        final double xStart = sStart + (i * cW);
        final double cx = xStart + (cW * 0.5);
        final double cy = r.top + (r.height * setGridYPos);

        // Visualize the circular detection point
        canvas.drawCircle(Offset(cx, cy), 4, setPaint);

        // Visualize the rectangular scan zone
        final double zoneW = cW * setZoneWidth;
        final double zoneH = r.height * setZoneHeight;
        final zoneRect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: zoneW,
          height: zoneH,
        );
        canvas.drawRect(zoneRect, gridPaint);
      }
    }

    for (var p in setBubbles) {
      canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height), 12, setPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BoxAlignmentPainter oldDelegate) => true;
}
