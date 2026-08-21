# Project Context: Checkmate LMS (Business Rule Compliant)

## Business Rules (BR-01 to BR-13)
The system strictly enforces the following business rules as its core functional requirements.

| BR ID | Rule Statement | System Requirement |
| :--- | :--- | :--- |
| **BR-01** | **Role-Agnostic Onboarding & Participation** | The system shall support user registration, authentication, class creation, and class enrollment while assigning the appropriate class-based role (Instructor for creator, Student for enrollee). |
| **BR-02** | **Instructor-Controlled Assessment Creation** | The system shall allow instructors to create assessments manually or through AI-assisted generation, verify generated content, and regenerate rejected content based on instructor feedback. Only MCQ and TF types are supported. |
| **BR-03** | **Assessment Approval Gate** | The system shall restrict personalized answer-sheet generation to approved assessments. Unapproved assessments remain locked. |
| **BR-04** | **Personalized Answer Sheet Generation** | The system shall generate personalized printable answer sheets containing student/assessment info and a unique Sheet ID (QR) for automatic identification. |
| **BR-05** | **Automated Sheet Identification** | The system shall automatically resolve the identity and assessment information of a scanned answer sheet using its unique Sheet ID before OMR grading. |
| **BR-06** | **Local Edge OMR Processing** | The system shall perform local OMR image processing and grading on the smartphone, including answer detection and flagging ambiguities, without uploading raw images to the backend. |
| **BR-07** | **Instructor-Controlled Scanning Session** | The system shall allow instructors to conduct an individual scanning session and synchronize the accumulated local grading results only after the session is completed ("FINISH SESSION"). |
| **BR-08** | **Session Synchronization Gate** | The system shall synchronize and persist locally graded results before aggregating assessment data and initiating AI-based class performance analysis. |
| **BR-09** | **Class-Wide AI Performance Analysis** | The system shall analyze finalized class assessment results using AI to provide topic-level summaries, identify common misconceptions, and generate teaching recommendations. |
| **BR-10** | **Comprehensible Narrative AI Insights** | The system shall generate personalized AI feedback based on the student's results and course content, providing supportive explanations and actionable improvement steps. |
| **BR-11** | **Controlled Result Release** | The system shall allow instructors to review results and AI analysis and explicitly finalize and release results before students can access them. |
| **BR-12** | **Student Access Control** | The system shall provide students with secure access to their own released scores, itemized results, and AI insights, while restricting access to others' data. |
| **BR-13** | **AI & Local Processing Separation** | The system shall use local OMR processing for deterministic answer-sheet grading and reserve AI processing for assessment content generation and performance analysis. |

## The Tech Stack
* **Frontend:** Flutter (Local OpenCV OMR, Isolate-based threading).
* **Backend:** FastAPI (Data orchestration, AI mediation, Auth verification).
* **Database:** Supabase (Auth, RLS, Relational persistence, Encryption at rest).
* **AI Engine:** Llama 3.2:3b (Local for Demo - 128K context, high speed).

## Security & Compliance
1.  **Authentication:** JWT-based Auth via Supabase (Email/Password & Google Login).
2.  **Encryption:** Data encrypted at rest via Supabase (TDE) and in transit via SSL/TLS.
3.  **Privacy (BR-12):** Row Level Security (RLS) ensures students only see their own released results.
4.  **OpenCV Location:** ALL OpenCV processing happens locally in Flutter (`opencv_dart`). Do NOT write Python OpenCV code.
2.  **Deterministic Grading:** AI is strictly forbidden from being used for raw OMR grading. Grading must be deterministic (pixel density analysis).
3.  **Data Syncing:** Results are held locally during a scanning session. A "Finish Session" action triggers a single batch sync to the FastAPI backend (BR-07).
4.  **Scope Limitation:** The grading system strictly uses Optical Mark Recognition (OMR). No handwritten text recognition (OCR).

## Core Workflows (Compliant)

### 1. Assessment Creation & Approval (BR-02, BR-03)
*   Instructor generates questions via AI or manual input.
*   **Approval Gate:** Instructor must manually approve the exam content.
*   The system locks answer-sheet generation until approval is toggled.

### 2. Scanning & Identification (BR-05, BR-06)
*   Flutter decodes QR (Sheet ID).
*   **Metadata Resolve:** App calls `/resolve-sheet` to get the Student Name and Answer Key.
*   **Local Grading:** App processes ROI bubbles and flags ambiguities locally.

### 3. Synchronization & Analysis (BR-08, BR-09, BR-10)
*   Instructor clicks "Finish Session".
*   App uploads all results in a single JSON batch to `/batch-save-grades`.
*   Backend triggers AI to generate topic-level summaries and personalized student insights.
