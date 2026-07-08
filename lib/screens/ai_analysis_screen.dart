import 'package:flutter/material.dart';

class AIAnalysisScreen extends StatefulWidget {
  const AIAnalysisScreen({super.key});

  @override
  State<AIAnalysisScreen> createState() => _AIAnalysisScreenState();
}

class _AIAnalysisScreenState extends State<AIAnalysisScreen> {
  int _phase = 0; // 0: Scanning, 1: Result

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  void _runAnalysis() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _phase = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Analysis Result'),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _phase == 0 ? _buildScanningUI() : _buildResultsUI(),
      ),
    );
  }

  Widget _buildScanningUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(strokeWidth: 8),
          ),
          SizedBox(height: 32),
          Text(
            'Analyzing Answer Sheet...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text('Comparing marks with course knowledge base'),
        ],
      ),
    );
  }

  Widget _buildResultsUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScoreCard(),
          const SizedBox(height: 32),
          const Text('Topic Mastery Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildTopicBar('Signal Theory', 0.95),
          _buildTopicBar('Filter Design', 0.60),
          _buildTopicBar('Fast Fourier Transform', 0.88),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('COMPLETE SCANNING SESSION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 35,
            backgroundColor: Colors.green,
            child: Icon(Icons.check, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('Student: John Doe', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('ID: 2024-0012', style: TextStyle(color: Colors.grey)),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('Score', '45/50'),
              _buildStat('Grade', '1.25'),
              _buildStat('Status', 'PASSED'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTopicBar(String name, double val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name),
              Text('${(val * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: val,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(val > 0.7 ? Colors.blue : Colors.orange),
          ),
        ],
      ),
    );
  }
}
