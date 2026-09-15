import 'package:opencv_dart/opencv_dart.dart' as cv;

/// OMR Template Configuration for the 30-Question Answer Sheet (30_questions.png)
class Standard30QuestionsTemplate {
  // Dimensions expected by this template (aspect ratio is key)
  static const int expectedWidth = 1240; // Example A4-ish width
  static const int expectedHeight = 3508; // Example height

  // Name Box ROI relative coordinates (Percentage 0.0 - 1.0)
  // Adjusted for standard A4 header space
  static const double nameRoiX = 0.05;
  static const double nameRoiY = 0.05;
  static const double nameRoiW = 0.90;
  static const double nameRoiH = 0.15;

  // The total number of questions on this sheet
  static const int totalQuestions = 30;

  // Question Grid Configuration
  // Adjust these percentages based on where the bubbles actually are in 30_questions.png
  
  // Starting X/Y of the first bubble (Q1, Option A)
  static const double gridStartX = 0.25; 
  static const double gridStartY = 0.28; 

  // Width of the bubble area and height of the bubble area
  static const double gridWidth = 0.65;
  static const double gridHeight = 0.65;

  // Option columns (A, B, C, D)
  static const int optionsPerQuestion = 4;
  
  // How questions are laid out. In this template, it looks like a single column of 30 questions
  // based on standard A4 vertical space, but we assume grid dimensions.
  // If it's 2 columns of 15, change this. Assuming 1 column of 30 for now.
  static const int columns = 1; 
  static const int rowsPerColumn = 30;

  /// Returns the estimated Rect for a specific question and option bubble
  /// using relative coordinates (0.0 to 1.0) multiplied by the image dimensions.
  static cv.Rect getBubbleRect(int questionIndex, int optionIndex, int imageWidth, int imageHeight) {
    // Basic grid math (adjusting for single column of 30)
    
    // Calculate relative size of a single cell
    double cellW = gridWidth / optionsPerQuestion;
    double cellH = gridHeight / rowsPerColumn;

    // Calculate relative position
    double relativeX = gridStartX + (optionIndex * cellW);
    double relativeY = gridStartY + (questionIndex * cellH);

    // Convert to absolute pixels
    int x = (relativeX * imageWidth).round();
    int y = (relativeY * imageHeight).round();
    int w = ((cellW * 0.8) * imageWidth).round(); // 0.8 to pad the bubble tightly
    int h = ((cellH * 0.8) * imageHeight).round();

    return cv.Rect(x, y, w, h);
  }
}
