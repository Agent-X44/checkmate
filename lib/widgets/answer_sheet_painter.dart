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

    // Calculate column dimensions
    final double left = size.width * template.answerRegion.left;
    final double top = size.height * template.answerRegion.top;
    final double totalWidth = size.width * template.answerRegion.width;
    final double totalHeight = size.height * template.answerRegion.height;

    final double spacing = template.columnSpacing * size.width;
    final double columnWidth = (totalWidth - (spacing * (template.columns - 1))) / template.columns;
    
    final int questionsPerColumn = (template.totalQuestions / template.columns).ceil();
    final double rowHeight = totalHeight / questionsPerColumn;

    for (int col = 0; col < template.columns; col++) {
      final double colX = left + col * (columnWidth + spacing);
      
      // Draw Column Outline
      if (template.showColumnOutlines) {
        canvas.drawRect(
          Rect.fromLTWH(colX, top, columnWidth, totalHeight),
          paint,
        );
      }

      // Draw Questions and Bubbles
      for (int q = 0; q < questionsPerColumn; q++) {
        final int questionIndex = col * questionsPerColumn + q;
        if (questionIndex >= template.totalQuestions) break;

        final double rowY = top + q * rowHeight;
        
        // Question Number (Outside)
        textPainter.text = TextSpan(
          text: '${questionIndex + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(colX - textPainter.width - 8, rowY + (rowHeight / 2) - (textPainter.height / 2)));

        // Choice Bubbles (Inside)
        final double bubbleAreaWidth = columnWidth - (template.innerPadding * size.width * 2);
        final double bubbleSpacing = bubbleAreaWidth / (template.choicesPerQuestion + 1);
        final double bubbleStartX = colX + (template.innerPadding * size.width);

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
