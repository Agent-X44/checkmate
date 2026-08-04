import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/omr/bubble_sheet_template.dart';
import 'dart:math' as math;

class TemplateService {
  /// Extracts the main bubble region from the warped paper.
  static cv.Mat extractAnswerRegion(cv.Mat warped, BubbleSheetTemplate template, {double xOffset = 0.0}) {
    if (warped.isEmpty) return warped;
    final int h = warped.height;
    final int w = warped.width;
    
    final int rectX = ((template.answerRegion.left + xOffset) * w).toInt().clamp(0, w - 1);
    final int rectY = (template.answerRegion.top * h).toInt().clamp(0, h - 1);
    final int rectW = (template.answerRegion.width * w).toInt().clamp(1, w - rectX);
    final int rectH = (template.answerRegion.height * h).toInt().clamp(1, h - rectY);

    final rect = cv.Rect(rectX, rectY, rectW, rectH);
    return warped.region(rect);
  }

  /// Splits the answer region into individual question rows using Horizontal Projection Profiles.
  static List<cv.Mat> splitQuestions(
    cv.Mat answerArea, 
    BubbleSheetTemplate template, 
    {int yOffset = 60}
  ) {
    if (answerArea.isEmpty) return [];

    // 1. Prepare Binary Image
    cv.Mat binary;
    if (answerArea.channels == 1) {
      binary = answerArea.clone();
    } else {
      final gray = cv.cvtColor(answerArea, cv.COLOR_BGR2GRAY);
      final (_, otsu) = cv.threshold(gray, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU);
      binary = otsu;
      gray.dispose();
    }
    
    // 2. Horizontal Projection (Row Sums)
    // We sum up the white pixels in each row. Peaks = Row centers.
    // Using simple row-by-row count for reliability
    final int w = binary.width;
    final int h = binary.height;
    final List<int> rowSums = List.generate(h, (y) {
       final row = binary.region(cv.Rect(0, y, w, 1));
       final count = cv.countNonZero(row);
       row.dispose();
       return count;
    });

    // 3. Find Row Centers (Peaks in density)
    final List<int> peakIndices = [];

    // Smooth the sums slightly to avoid noisy spikes
    final smoothed = List<int>.from(rowSums);
    for (int i = 2; i < h - 2; i++) {
      smoothed[i] = ((rowSums[i-2] + rowSums[i-1] + rowSums[i] + rowSums[i+1] + rowSums[i+2]) / 5).toInt();
    }

    // Identify local maxima that are significant
    final int threshold = (smoothed.reduce(math.max) * 0.3).toInt(); // 30% of max density
    for (int i = 5; i < h - 5; i++) {
      if (smoothed[i] > threshold &&
          smoothed[i] >= smoothed[i-1] && smoothed[i] >= smoothed[i+1] &&
          smoothed[i] >= smoothed[i-2] && smoothed[i] >= smoothed[i+2]) {

        // Prevent picking multiple points for the same wide peak
        if (peakIndices.isEmpty || (i - peakIndices.last) > (h / (template.totalQuestions * 1.5))) {
          peakIndices.add(i);
        }
      }
    }

    // 4. Create Consistency: Fallback to geometric if peaks don't match question count
    final List<cv.Mat> rowMats = [];

    // and add a vertical offset to ensure bubbles are centered in the strip.
    const int startX = 0;
    final int rowW = answerArea.width; 

    if (peakIndices.length >= template.totalQuestions) {
       // We have clear peaks for every row!
       // Calculate fixed row height from peak distance
       int totalDist = 0;
       for (int j = 1; j < peakIndices.length; j++) {
         totalDist += (peakIndices[j] - peakIndices[j-1]);
       }
       final int avgRowHeight = (totalDist / (peakIndices.length - 1)).toInt();

       // Use a consistent crop height based on the physical shading size
       // Adding a 20% height buffer to prevent cutting the top of bubbles
       final int cropHeight = (avgRowHeight * 1.2).toInt();

       for (int i = 0; i < template.totalQuestions; i++) {
         final int centerY = peakIndices[i] + yOffset;
         final int startY = math.max(0, math.min(h - 1, centerY - (cropHeight ~/ 2)));
         final int actualH = math.min(h - startY, cropHeight);

         if (actualH > 0 && startX + rowW <= answerArea.width) {
           rowMats.add(answerArea.region(cv.Rect(startX, startY, rowW, actualH)));
         }
       }
    } else {
       // Fallback to geometric split if peaks are messy
       final double rowH = h / template.totalQuestions;
       for (int i = 0; i < template.totalQuestions; i++) {
         final int centerY = ((i + 0.5) * rowH).toInt() + yOffset;
         final int startY = math.max(0, math.min(h - 1, centerY - (rowH ~/ 2).toInt()));
         final int actualH = math.min(h - startY, rowH.toInt());
         
         if (actualH > 0 && startX + rowW <= answerArea.width) {
           rowMats.add(answerArea.region(cv.Rect(startX, startY, rowW, actualH)));
         }
       }
    }

    binary.dispose();
    return rowMats;
  }
}
