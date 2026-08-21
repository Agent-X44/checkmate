# Implementation Plan: Local Llama 3 8B Integration (Ollama)

This plan pivots the backend to host **Llama 3 8B** locally using **Ollama**. This ensures 100% data privacy and works without a cloud API key.

## User Review Required

> [!IMPORTANT]
> You must have **Ollama** installed and running on your machine.
> Download it from [ollama.com](https://ollama.com/).
> Run the model once in your terminal to ensure it's downloaded:
> `ollama run llama3:8b`

## Proposed Changes

### Backend Component

#### [MODIFY] [main.py](file:///C:/AndroidStudioProjects/checkmate/backend/main.py)
- Remove `groq` dependency.
- Implement `Ollama` API calls using the `requests` library.
- Target `http://localhost:11434/api/chat`.
- Maintain the same structured JSON output for Flutter compatibility.

#### [MODIFY] [requirements.txt](file:///C:/AndroidStudioProjects/checkmate/backend/requirements.txt)
- Remove `groq`.
- Add `requests`.

## Verification Plan

### Automated Tests
1.  Ensure Ollama is running (`ollama list` should show `llama3:8b`).
2.  Run FastAPI: `uvicorn main:app --reload`.
3.  Test the `/generate-exam` endpoint:
    ```bash
    curl -X POST "http://localhost:8000/generate-exam" -H "Content-Type: application/json" -d '{"topic": "Flutter Development", "question_count": 2}'
    ```

### Manual Verification
1.  Open the Checkmate app.
2.  Generate an exam and verify the terminal running Ollama shows processing activity.
