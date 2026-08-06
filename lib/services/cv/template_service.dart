import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/omr/bubble_sheet_template.dart';
import 'dart:math' as math;

class TemplateService {
  /// Detects the largest rectangular boxes (potential column containers) in the image.
  /// Returns a list of Rects in normalized coordinates.
  static List<Rect> detectColumnBoxes(cv.Mat thresholded) {
    final List<Rect> detectedBoxes = [];
    final int w = thresholded.width;
    final int h = thresholded.height;

    // 1. Find Contours
    final (contours, _) = cv.findContours(thresholded, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

    for (int i = 0; i < contours.length; i++) {
      final area = cv.contourArea(contours[i]);
      final double imgArea = (w * h).toDouble();

      // We are looking for large boxes (at least 15% of the paper area)
      if (area > imgArea * 0.10) {
        final perimeter = cv.arcLength(contours[i], true);
        final approx = cv.approxPolyDP(contours[i], 0.02 * perimeter, true);

        if (approx.length == 4) {
          final rect = cv.boundingRect(contours[i]);
          
          // Filter by aspect ratio (columns are usually tall and narrow)
          final double ratio = rect.width / rect.height;
          if (ratio > 0.2 && ratio < 0.8) {
            detectedBoxes.add(Rect.fromLTWH(
              rect.x / w, 
              rect.y / h, 
              rect.width / w, 
              rect.height / h
            ));
          }
        }
      }
    }

    // Sort boxes from left to right
    detectedBoxes.sort((a, b) => a.left.compareTo(b.left));
    
    return detectedBoxes;
  }

  /// Extracts a specific rectangular region from the warped paper.
  static cv.Mat extractRegion(cv.Mat warped, Rect region, {double xOffset = 0.0}) {
    if (warped.isEmpty) return warped;
    final int h = warped.height;
    final int w = warped.width;
    
    final int rectX = ((region.left + xOffset) * w).toInt().clamp(0, w - 1);
    final int rectY = (region.top * h).toInt().clamp(0, h - 1);
    final int rectW = (region.width * w).toInt().clamp(1, w - rectX);
    final int rectH = (region.height * h).toInt().clamp(1, h - rectY);

    final rect = cv.Rect(rectX, rectY, rectW, rectH);
    return warped.region(rect);
  }

  /// Extracts the main bubble regions from the warped paper.
  @Deprecated('Use extractRegion directly in a loop')
  static cv.Mat extractAnswerRegion(cv.Mat warped, BubbleSheetTemplate template, {double xOffset = 0.0}) {
    return extractRegion(warped, template.answerRegions.first, xOffset: xOffset);
  }

  /// Splits the answer region into individual question rows.
  static List<cv.Mat> splitQuestions(
    cv.Mat answerArea, 
    int questionsInThisRegion,
    {int yOffset = 60, double heightMultiplier = 1.2, double ySpace = 0.0}
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
    final int w = binary.width;
    final int h = binary.height;
    final List<int> rowSums = List.generate(h, (y) {
       final row = binary.region(cv.Rect(0, y, w, 1));
       final count = cv.countNonZero(row);
       row.dispose();
       return count;
    });

    // 3. Find Row Centers
    final List<int> peakIndices = [];
    final smoothed = List<int>.from(rowSums);
    for (int i = 2; i < h - 2; i++) {
      smoothed[i] = ((rowSums[i-2] + rowSums[i-1] + rowSums[i] + rowSums[i+1] + rowSums[i+2]) / 5).toInt();
    }

    final int threshold = (smoothed.reduce(math.max) * 0.3).toInt();
    for (int i = 5; i < h - 5; i++) {
      if (smoothed[i] > threshold &&
          smoothed[i] >= smoothed[i-1] && smoothed[i] >= smoothed[i+1] &&
          smoothed[i] >= smoothed[i-2] && smoothed[i] >= smoothed[i+2]) {

        if (peakIndices.isEmpty || (i - peakIndices.last) > (h / (questionsInThisRegion * 1.5))) {
          peakIndices.add(i);
        }
      }
    }

    final List<cv.Mat> rowMats = [];
    const int startX = 0;
    final int rowW = answerArea.width; 

    if (peakIndices.length >= questionsInThisRegion) {
       int totalDist = 0;
       for (int j = 1; j < peakIndices.length; j++) {
         totalDist += (peakIndices[j] - peakIndices[j-1]);
       }
       final int avgRowHeight = (totalDist / (peakIndices.length - 1)).toInt();
       final int cropHeight = (avgRowHeight * heightMultiplier).toInt();

       for (int i = 0; i < questionsInThisRegion; i++) {
         final int centerY = (peakIndices[i] + yOffset + (i * ySpace)).toInt();
         final int startY = math.max(0, math.min(h - 1, centerY - (cropHeight ~/ 2)));
         final int actualH = math.min(h - startY, cropHeight);

         if (actualH > 0 && startX + rowW <= answerArea.width) {
           rowMats.add(answerArea.region(cv.Rect(startX, startY, rowW, actualH)));
         }
       }
    } else {
       final double rowH = h / questionsInThisRegion;
       for (int i = 0; i < questionsInThisRegion; i++) {
         final int centerY = ((i + 0.5) * rowH).toInt() + yOffset + (i * ySpace).toInt();
         final int startY = math.max(0, math.min(h - 1, centerY - ((rowH * heightMultiplier) / 2).toInt()));
         final int actualH = math.min(h - startY, (rowH * heightMultiplier).toInt());
         
         if (actualH > 0 && startX + rowW <= answerArea.width) {
           rowMats.add(answerArea.region(cv.Rect(startX, startY, rowW, actualH)));
         }
       }
    }

    binary.dispose();
    return rowMats;
  }
}
