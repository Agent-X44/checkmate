import 'package:flutter/material.dart';
import '../models/omr/bubble_sheet_template.dart';

class AnswerSheetPainter extends CustomPainter {
  final BubbleSheetTemplate template;

  AnswerSheetPainter({required this.template});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Calculate dimensions for each answer region
    final int questionsPerRegion = (template.totalQuestions / template.answerRegions.length).ceil();

    for (int i = 0; i < template.answerRegions.length; i++) {
      final region = template.answerRegions[i];
      final double left = size.width * region.left;
      final double top = size.height * region.top;
      final double totalWidth = size.width * region.width;
      final double totalHeight = size.height * region.height;

      // Draw Column Outline
      if (template.showColumnOutlines) {
        canvas.drawRect(
          Rect.fromLTWH(left, top, totalWidth, totalHeight),
          paint,
        );
      }

      final int questionsInThisRegion = (i == template.answerRegions.length - 1) 
          ? template.totalQuestions - (questionsPerRegion * i)
          : questionsPerRegion;
      
      final double rowHeight = totalHeight / questionsInThisRegion;

      // Draw Questions and Bubbles
      for (int q = 0; q < questionsInThisRegion; q++) {
        final int questionIndex = i * questionsPerRegion + q;
        if (questionIndex >= template.totalQuestions) break;

        final double rowY = top + q * rowHeight;
        
        // Question Number (Outside)
        textPainter.text = TextSpan(
          text: '${questionIndex + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(left - textPainter.width - 8, rowY + (rowHeight / 2) - (textPainter.height / 2)));

        // Choice Bubbles (Inside)
        final double bubbleAreaWidth = totalWidth - (template.innerPadding * size.width * 2);
        final double bubbleSpacing = bubbleAreaWidth / (template.choicesPerQuestion + 1);
        final double bubbleStartX = left + (template.innerPadding * size.width);

        for (int c = 0; c < template.choicesPerQuestion; c++) {
          final double bubbleX = bubbleStartX + (c + 1) * bubbleSpacing;
          final double bubbleY = rowY + (rowHeight / 2);
          
          canvas.drawCircle(Offset(bubbleX, bubbleY), 7, paint);
          
          final String label = String.fromCharCode(65 + c); // A, B, C...
          textPainter.text = TextSpan(
            text: label,
            style: const TextStyle(color: Colors.black, fontSize: 8),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(bubbleX - textPainter.width / 2, bubbleY - textPainter.height / 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
