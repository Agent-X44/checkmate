import 'package:flutter/material.dart';

class AIQuestionnaireScreen extends StatefulWidget {
  final String type; 
  const AIQuestionnaireScreen({super.key, required this.type});

  @override
  State<AIQuestionnaireScreen> createState() => _AIQuestionnaireScreenState();
}

class _AIQuestionnaireScreenState extends State<AIQuestionnaireScreen> {
  final TextEditingController _inputController = TextEditingController(
    text: 'Introduction to Signal Processing and System Analysis',
  );
  int _currentStep = 0; // 0: Input, 1: Generating, 2: Review
  List<String> _mockQuestions = [];

  void _startGeneration() async {
    if (_inputController.text.trim().isEmpty) return;
    
    setState(() => _currentStep = 1);

    // Fast simulation for a snappy demo
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _mockQuestions = [
          "1. What is the primary purpose of ${_inputController.text}?",
          "2. Compare and contrast the two main methods in this field.",
          "3. Multiple Choice: Which scientist first proposed this theory?",
          "4. Explain the impact of this topic on modern technology.",
        ];
        _currentStep = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI ${widget.type} Builder'),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case 0:
        return _buildInputStep();
      case 1:
        return _buildGeneratingStep();
      case 2:
        return _buildReviewStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildInputStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Content Source',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Enter a topic or paste existing questions for the AI to process.'),
          const SizedBox(height: 24),
          TextField(
            controller: _inputController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'e.g., "Principles of Digital Logic" or paste raw text...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(50),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _startGeneration,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('GENERATE QUESTIONNAIRE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'AI is analyzing your content...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('Mapping data for future OMR analysis'),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Questionnaire Ready',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._mockQuestions.map((q) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(q),
          ),
        )),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('EDIT SOURCE'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('AI Knowledge base updated for this course!'))
                  );
                  Navigator.pop(context);
                },
                child: const Text('SAVE & FINALIZE'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
