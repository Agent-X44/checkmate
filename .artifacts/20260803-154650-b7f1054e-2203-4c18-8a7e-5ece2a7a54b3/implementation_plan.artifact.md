# Fix OMR Row Extraction Width and Vertical Centering

This plan addresses the request to fix the width of the choice rows and add a vertical offset to ensure they are centered correctly after peak detection.

## Proposed Changes

### [Template Service](file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/template_service.dart)

- Modify `splitQuestions` to include a vertical offset when calculating the crop region for each row.
- Adjust the width of the extracted row to focus on the choices area (right-aligned, ~75% of the total answer region width).

#### [template_service.dart](file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/template_service.dart)

```diff
-         final int centerY = peakIndices[i];
-         final int startY = math.max(0, centerY - (cropHeight ~/ 2));
+         // Add a small vertical offset to center the bubbles better in the strip
+         const int yOffset = 2;
+         final int centerY = peakIndices[i] + yOffset;
+         final int startY = math.max(0, centerY - (cropHeight ~/ 2));
          final int actualH = math.min(h - startY, cropHeight);

-         rowMats.add(answerArea.region(cv.Rect(0, startY, answerArea.width, actualH)));
+         // Fix the width to focus on the right 75% where the bubbles are
+         final int rowW = (answerArea.width * 0.75).toInt();
+         final int startX = (answerArea.width - rowW);
+         rowMats.add(answerArea.region(cv.Rect(startX, startY, rowW, actualH)));
```

### [Bubble Detection Service](file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/bubble_detection_service.dart)

- Update `detectFilledBubble` to reflect that the input `rowMat` is already narrowed down to the choices area.

#### [bubble_detection_service.dart](file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/bubble_detection_service.dart)

```diff
-    final double gridStartX = w * 0.20;
-    final double gridWidth = w * 0.80;
+    // The rowMat is now already focused on the choice area (the right 75% of the answer region)
+    // We can use the full width or a very small margin.
+    final double gridStartX = w * 0.02; // Small 2% margin
+    final double gridWidth = w * 0.96;
```

## Verification Plan

### Automated Tests
- I will verify the changes by running the OMR process on a sample image if available, or by inspecting the code logic.
- Since I don't have a full testing environment with camera input, I will use `analyze_file` to ensure no syntax errors.

### Manual Verification
- Inspect the logic in `TemplateService.splitQuestions` to ensure the `Rect` boundaries are safe.
- Verify that `BubbleDetectionService` still maps choices correctly given the narrower input.
