# OMR Debugger Tools Walkthrough

I have implemented a set of debugging tools that allow you to tune the OMR alignment in real-time directly on the results screen.

## Features

### 1. Interactive Debug Sliders
- **Y-Offset Slider**: Adjust the vertical centering of the bubbles within the extracted strips.
- **Grid Start Slider**: Adjust where the bubble detection grid begins (skipping question numbers).
- **Grid Width Slider**: Adjust how far the detection grid stretches horizontally across the strip.

### 2. Real-time Feedback
- Toggling the **bug icon** in the top right of the Evaluation Result screen reveals the sliders.
- As you move the sliders, the app **re-processes the images locally** using OpenCV and updates the detected answers and confidence scores instantly.
- A **yellow visual indicator** appears below each strip to show you exactly where the 5 detection cells are currently mapped.

## Technical Implementation
- **Local Re-processing**: The `AIAnalysisScreen` now decodes the warped image and re-runs the `splitQuestions` and `detectFilledBubble` algorithms on every slider change.
- **Algorithm Exposure**: Updated `TemplateService` and `BubbleDetectionService` to accept optional alignment parameters, moving away from hardcoded "magic numbers."

## How to Use
1. Scan a paper as usual.
2. On the **Evaluation Result** screen, tap the **bug icon** in the top right.
3. Use the sliders to move the strips up/down or shift the A-E cells until the answers are 100% accurate.
4. Note the values (e.g., Y-Offset 60, Grid Start 0.12) if you want them permanently hardcoded in the future.

render_diffs(file:///C:/AndroidStudioProjects/checkmate/lib/screens/ai_analysis_screen.dart)
render_diffs(file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/template_service.dart)
render_diffs(file:///C:/AndroidStudioProjects/checkmate/lib/services/cv/bubble_detection_service.dart)
