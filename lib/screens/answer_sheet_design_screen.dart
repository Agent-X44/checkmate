import 'package:flutter/material.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../widgets/answer_sheet_painter.dart';
import '../services/pdf_generator.dart';

class AnswerSheetDesignScreen extends StatefulWidget {
  const AnswerSheetDesignScreen({super.key});

  @override
  State<AnswerSheetDesignScreen> createState() =>
      _AnswerSheetDesignScreenState();
}

class _AnswerSheetDesignScreenState extends State<AnswerSheetDesignScreen> {
  final List<BubbleSheetTemplate> _templates = [
    const BubbleSheetTemplate(
      name: 'Standard 50 Questions',
      answerRegions: [
        Rect.fromLTRB(0.04, 0.38, 0.48, 0.91), // Left Column Box
        Rect.fromLTRB(0.52, 0.38, 0.96, 0.91), // Right Column Box
      ],
      totalQuestions: 50,
      choicesPerQuestion: 4, // A, B, C, D to match sample
      columns: 2,
      showColumnOutlines: true,
      columnSpacing: 0.08,
      qrRegion: Rect.fromLTRB(0.68, 0.1, 0.94, 0.22),
    ),
    const BubbleSheetTemplate(
      name: 'Compact 100 Questions',
      answerRegions: [Rect.fromLTRB(0.1, 0.05, 0.9, 0.95)],
      totalQuestions: 100,
      choicesPerQuestion: 4,
      columns: 4,
      showColumnOutlines: true,
      columnSpacing: 0.04,
    ),
    const BubbleSheetTemplate(
      name: 'Quick Quiz (20 Questions)',
      answerRegions: [Rect.fromLTRB(0.2, 0.1, 0.8, 0.9)],
      totalQuestions: 20,
      choicesPerQuestion: 5,
      columns: 1,
      showColumnOutlines: true,
    ),
  ];

  late BubbleSheetTemplate _selectedTemplate;
  bool _isDebugAlignment = false;
  String _selectedStudent = "JOHN DOE";

  // Alignment Debug Values
  double _nameTop = 87.1;
  double _nameLeft = 145.0;
  double _nameScale = 1.2;
  double _qrTop = 33.0;
  double _qrRight = 65.4;
  double _qrSize = 118.4;

  @override
  void initState() {
    super.initState();
    _selectedTemplate = _templates.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Design Answer Sheet'),
        actions: [
          IconButton(
            icon: Icon(_isDebugAlignment ? Icons.grid_on : Icons.grid_off),
            onPressed: () =>
                setState(() => _isDebugAlignment = !_isDebugAlignment),
            tooltip: "Debug Alignment",
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview Section
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade200,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: AspectRatio(
                    aspectRatio: 0.707, // A4 Portrait
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            25 * 0.5, // side margin scaled
                            35 * 0.5, // top margin scaled
                            25 * 0.5,
                            25 * 0.5),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (_selectedTemplate.name ==
                                'Standard 50 Questions') ...[
                              Positioned.fill(
                                  child: Image.asset('assets/50_questions.png',
                                      fit: BoxFit.contain)),
                              if (_isDebugAlignment) ...[
                                // Name/Set Overlay Preview
                                Positioned(
                                  top: (_nameTop - 20) * 0.5,
                                  left: (_nameLeft - 85) * 0.5,
                                  child: Transform.scale(
                                    scale: _nameScale *
                                        0.5, // 0.5 for preview scaling
                                    alignment: Alignment.topLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text('Name: ',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black)),
                                            Container(
                                              decoration: const BoxDecoration(
                                                  border: Border(
                                                      bottom: BorderSide(
                                                          width: 1))),
                                              child: Text(_selectedStudent,
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 15),
                                        Row(
                                          children: [
                                            const Text('Set: ',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black)),
                                            _miniCheckbox('A', false),
                                            const SizedBox(width: 20),
                                            _miniCheckbox('B', false),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // QR and Sheet ID Overlay Preview (Centered)
                                Positioned(
                                  top: _qrTop * 0.5,
                                  right: _qrRight * 0.5,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: _qrSize * 0.5,
                                        height: _qrSize * 0.5,
                                        color: Colors.grey.shade300,
                                        child: const Center(
                                            child:
                                                Icon(Icons.qr_code, size: 20)),
                                      ),
                                      const SizedBox(height: 2.5),
                                      const Text(
                                        'Sheet ID: CM50-A-0001',
                                        style: TextStyle(
                                          fontSize: 4.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],

                            if (_selectedTemplate.name !=
                                'Standard 50 Questions')
                              CustomPaint(
                                painter: AnswerSheetPainter(
                                    template: _selectedTemplate),
                                size: Size.infinite,
                              ),

                            // Debug Overlay Indicators (Scaled roughly to preview size)
                            if (_isDebugAlignment) ...[
                              _buildDebugBox(
                                  "NAME", _nameTop, _nameLeft, null, null),
                              _buildDebugBox(
                                  "QR", _qrTop, null, _qrRight, null),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_isDebugAlignment)
            Expanded(flex: 2, child: _buildAlignmentSliders()),

          // Selection Section
          if (!_isDebugAlignment)
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SELECT LAYOUT',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey),
                          ),
                          DropdownButton<String>(
                            value: _selectedStudent,
                            items: ["JOHN DOE", "JANE DOE"]
                                .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s,
                                        style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedStudent = v!),
                            underline: Container(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _templates.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final template = _templates[index];
                          final isSelected = _selectedTemplate == template;
                          return ListTile(
                            selected: isSelected,
                            onTap: () =>
                                setState(() => _selectedTemplate = template),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade300)),
                            leading: index == 0
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.asset(
                                        'assets/50_questions.png',
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover))
                                : Icon(index == 1
                                    ? Icons.grid_view
                                    : Icons.article),
                            title: Text(template.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${template.totalQuestions} Qs • ${template.columns} Columns'),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.blue)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Action Section
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _miniCheckbox(String label, bool isChecked) {
    return Row(
      children: [
        Container(
          width: 15,
          height: 15,
          decoration:
              BoxDecoration(border: Border.all(width: 1, color: Colors.black)),
          child: isChecked
              ? Center(
                  child: Container(width: 8, height: 8, color: Colors.black))
              : null,
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.black)),
      ],
    );
  }

  Widget _buildDebugBox(
      String label, double? t, double? l, double? r, double? b) {
    return Positioned(
      top: t != null ? t * 0.5 : null, // Scale for preview
      left: l != null ? l * 0.5 : null,
      right: r != null ? r * 0.5 : null,
      bottom: b != null ? b * 0.5 : null,
      child: Container(
        padding: const EdgeInsets.all(2),
        color: Colors.red.withValues(alpha: 0.3),
        child: Text(label,
            style: const TextStyle(
                fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildAlignmentSliders() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('NAME & SET OVERLAY',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue)),
          ),
          _slider("Top", _nameTop, 0, 400, (v) => setState(() => _nameTop = v)),
          _slider(
              "Left", _nameLeft, 0, 400, (v) => setState(() => _nameLeft = v)),
          _slider("Scale", _nameScale, 0.5, 2.0,
              (v) => setState(() => _nameScale = v)),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('QR CODE OVERLAY',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue)),
          ),
          _slider("Top", _qrTop, 0, 400, (v) => setState(() => _qrTop = v)),
          _slider(
              "Right", _qrRight, 0, 400, (v) => setState(() => _qrRight = v)),
          _slider("Size", _qrSize, 40, 150, (v) => setState(() => _qrSize = v)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _slider(String label, double val, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
            child:
                Slider(value: val, min: min, max: max, onChanged: onChanged)),
        SizedBox(
            width: 35,
            child: Text(val.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10))),
      ],
    );
  }

  Widget _buildActionButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                await PdfGenerator.generateAndPrint(
                  _selectedTemplate,
                  alignment: PdfAlignment(
                    nameTop: _nameTop,
                    nameLeft: _nameLeft,
                    nameScale: _nameScale,
                    qrTop: _qrTop,
                    qrRight: _qrRight,
                    qrSize: _qrSize,
                  ),
                  studentNames: [_selectedStudent],
                );
              },
              icon: const Icon(Icons.person),
              label: Text('EXPORT ONLY $_selectedStudent',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: () async {
                await PdfGenerator.generateAndPrint(
                  _selectedTemplate,
                  alignment: PdfAlignment(
                    nameTop: _nameTop,
                    nameLeft: _nameLeft,
                    nameScale: _nameScale,
                    qrTop: _qrTop,
                    qrRight: _qrRight,
                    qrSize: _qrSize,
                  ),
                  studentNames: [
                    "JOHN DOE",
                    "JANE DOE"
                  ], // The list of all students
                );
              },
              icon: const Icon(Icons.group),
              label: const Text('GENERATE FOR ALL STUDENTS',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }
}
