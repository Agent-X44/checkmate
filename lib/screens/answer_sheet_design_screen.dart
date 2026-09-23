import 'package:flutter/material.dart';
import '../models/omr/bubble_sheet_template.dart';
import '../models/omr/template_registry.dart';
import '../widgets/answer_sheet_painter.dart';
import '../services/pdf_generator.dart';

class AnswerSheetDesignScreen extends StatefulWidget {
  const AnswerSheetDesignScreen({super.key});

  @override
  State<AnswerSheetDesignScreen> createState() =>
      _AnswerSheetDesignScreenState();
}

class _AnswerSheetDesignScreenState extends State<AnswerSheetDesignScreen> {
  final List<BubbleSheetTemplate> _templates = AnswerSheetTemplateRegistry.all;

  late BubbleSheetTemplate _selectedTemplate;
  bool _isDebugAlignment = false;
  String _selectedStudent = "JOHN DOE";

  // Alignment Debug Values
  double _nameTop = 115.8;
  double _nameLeft = 172.5;
  double _nameScale = 1.0;
  double _qrTop = 57.0;
  double _qrRight = 99.6;
  double _qrSize = 107.0;

  @override
  void initState() {
    super.initState();
    _selectedTemplate = _templates.first;
    _loadAlignmentForTemplate(_selectedTemplate);
  }

  void _loadAlignmentForTemplate(BubbleSheetTemplate template) {
    _selectedTemplate = template;
    _nameTop = template.pdfAlignment.nameTop;
    _nameLeft = template.pdfAlignment.nameLeft;
    _nameScale = template.pdfAlignment.nameScale;
    _qrTop = template.pdfAlignment.qrTop;
    _qrRight = template.pdfAlignment.qrRight;
    _qrSize = template.pdfAlignment.qrSize;
  }

  Widget _buildPreview(bool isDark, Color bgColor, Color textColor) {
    return Expanded(
      flex: 3,
      child: Container(
        width: double.infinity,
        color: bgColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: AspectRatio(
              aspectRatio: 0.707, // A4 Portrait
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, // The paper itself should remain white
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(
                      20 * 0.5), // 20px margin scaled for 4 corners
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          _selectedTemplate.assetPath,
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                  color: Colors.grey.shade300,
                                  child: Center(
                                      child: Text('Image not found:\n${_selectedTemplate.assetPath}', style: const TextStyle(color: Colors.black)))),
                        ),
                      ),

                      if (_isDebugAlignment) ...[
                        Positioned(
                          top: (_nameTop - 20) * 0.5,
                          left: (_nameLeft - 85) * 0.5,
                          child: Transform.scale(
                            scale: _nameScale * 0.5,
                            alignment: Alignment.topLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Name: ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black, // always black on paper
                                      ),
                                    ),
                                    Container(
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(width: 1, color: Colors.black),
                                        ),
                                      ),
                                      child: Text(
                                        _selectedStudent,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    const Text(
                                      'Set: ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                    _miniCheckbox('1', false),
                                    const SizedBox(width: 20),
                                    _miniCheckbox('2', false),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: _qrTop * 0.5,
                          right: _qrRight * 0.5,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: _qrSize * 0.5,
                                height: _qrSize * 0.5,
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: Icon(Icons.qr_code, size: 20, color: Colors.black),
                                ),
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

                      if (_selectedTemplate.name != 'Standard 50 Questions' && _selectedTemplate.name != 'Standard 30 Questions')
                        CustomPaint(
                          painter: AnswerSheetPainter(
                            template: _selectedTemplate,
                          ),
                          size: Size.infinite,
                        ),

                      if (_isDebugAlignment) ...[
                        _buildDebugBox('NAME', _nameTop, _nameLeft, null, null),
                        _buildDebugBox('QR', _qrTop, null, _qrRight, null),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellow : Colors.blue;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Design Answer Sheet', style: TextStyle(color: textColor)),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: Icon(_isDebugAlignment ? Icons.grid_on : Icons.grid_off, color: textColor),
            onPressed: () =>
                setState(() => _isDebugAlignment = !_isDebugAlignment),
            tooltip: "Debug Alignment",
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview Section
          _buildPreview(isDark, bgColor, textColor),

          if (_isDebugAlignment)
            Expanded(flex: 2, child: _buildAlignmentSliders(isDark, bgColor, textColor, accentColor)),

          // Selection Section
          if (!_isDebugAlignment)
            Expanded(
              flex: 2,
              child: Container(
                color: bgColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SELECT LAYOUT',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textColor.withValues(alpha: 0.6)),
                          ),
                          DropdownButton<String>(
                            dropdownColor: isDark ? Colors.grey.shade900 : Colors.white,
                            value: _selectedStudent,
                            items: ["JOHN DOE", "JANE DOE"]
                                .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s,
                                        style: TextStyle(fontSize: 12, color: textColor))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedStudent = v!),
                            underline: Container(),
                            iconEnabledColor: textColor,
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
                                setState(() => _loadAlignmentForTemplate(template)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isSelected
                                        ? accentColor
                                        : (isDark ? Colors.grey.shade800 : Colors.grey.shade300))),
                            leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                    template.assetPath,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(Icons.article, color: textColor))),
                            title: Text(template.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, color: textColor)),
                            subtitle: Text(
                                '${template.totalQuestions} Qs • ${template.columns} Columns', style: TextStyle(color: textColor.withValues(alpha: 0.7))),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: accentColor)
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
          _buildActionButton(isDark, bgColor, textColor, accentColor),
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

  Widget _buildAlignmentSliders(bool isDark, Color bgColor, Color textColor, Color accentColor) {
    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('NAME & SET OVERLAY',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: accentColor)),
          ),
          _slider("Top", _nameTop, 0, 400, (v) => setState(() => _nameTop = v), textColor, accentColor),
          _slider(
              "Left", _nameLeft, 0, 400, (v) => setState(() => _nameLeft = v), textColor, accentColor),
          _slider("Scale", _nameScale, 0.5, 2.0,
              (v) => setState(() => _nameScale = v), textColor, accentColor),
          Divider(color: textColor.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('QR CODE OVERLAY',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: accentColor)),
          ),
          _slider("Top", _qrTop, 0, 400, (v) => setState(() => _qrTop = v), textColor, accentColor),
          _slider(
              "Right", _qrRight, 0, 400, (v) => setState(() => _qrRight = v), textColor, accentColor),
          _slider("Size", _qrSize, 40, 150, (v) => setState(() => _qrSize = v), textColor, accentColor),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _slider(String label, double val, double min, double max,
      ValueChanged<double> onChanged, Color textColor, Color accentColor) {
    return Row(
      children: [
        SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(fontSize: 11, color: textColor))),
        Expanded(
            child:
                Slider(value: val, min: min, max: max, onChanged: onChanged, activeColor: accentColor)),
        SizedBox(
            width: 35,
            child: Text(val.toStringAsFixed(1),
                style: TextStyle(fontSize: 10, color: textColor))),
      ],
    );
  }

  Widget _buildActionButton(bool isDark, Color bgColor, Color textColor, Color accentColor) {
    return Container(
      color: bgColor,
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
                  sheetData: [{'name': _selectedStudent, 'qrCode': 'CM-TEST-1234'}],
                );
              },
              icon: Icon(Icons.person, color: isDark ? Colors.black : Colors.white),
              label: Text('EXPORT ONLY $_selectedStudent',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.black : Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
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
                  sheetData: [
                    {'name': "JOHN DOE", 'qrCode': 'CM-BATCH-0001'},
                    {'name': "JANE DOE", 'qrCode': 'CM-BATCH-0002'}
                  ], // The list of all students
                );
              },
              icon: Icon(Icons.group, color: isDark ? Colors.black : Colors.white),
              label: Text('GENERATE FOR ALL STUDENTS',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.black : Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.red.shade300 : Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }
}
