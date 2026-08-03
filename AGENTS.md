# Project Context: Checkmate LMS

## Project Overview
Checkmate is a Google Classroom-style Learning Management System (LMS) that allows teachers to grade physical multiple-choice answer sheets locally via device camera, and generate new exams using AI.

## The Tech Stack
* **Frontend:** Flutter (Mobile UI, Camera Capture, and Computer Vision).
* **Backend:** FastAPI (Python).
* **Computer Vision:** `opencv_dart` running LOCALLY in Flutter via Dart FFI.
* **AI Engine:** Llama 3 (Exam generation, pedagogical insights, and analyzing graded results for reports).

## Strict Architectural Rules
1.  **OpenCV Location:** ALL OpenCV processing must happen locally in Flutter using the `opencv_dart` package. Do NOT write Python OpenCV code.
2.  **Live Camera Strategy:** The live camera stream (`startImageStream`) should ONLY be used for document edge detection (finding the paper). The actual bubble grading (OMR) must be performed on a high-resolution static capture.
3.  **Threading:** Live frame processing must be pushed to a Dart Isolate to prevent UI jank.
4.  **Local Grading Strategy:** OMR (Bubble Detection) must be performed LOCALLY using `opencv_dart` for maximum accuracy and zero latency. Llama 3 will be used for post-grading pedagogical analysis and insights.
5.  **Scope Limitation:** The grading system strictly uses Optical Mark Recognition (OMR) for standardized multiple-choice bubble sheets. No handwritten text recognition (OCR).