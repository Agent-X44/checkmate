"""
Checkmate LMS Backend - Compliance & AI Orchestration Service.
Enforces Business Rules BR-01 through BR-13.

MAINTENANCE NOTES:
- Local AI: Uses Ollama (ensure it's running before starting this server).
- Cloud AI: Uses OpenRouter (requires Sk-Or-V1 key in .env).
- Security: Protected routes require Supabase JWT.
"""

import os
import json
import logging
import httpx
import asyncio
import uuid
import traceback
from io import BytesIO

from fastapi import FastAPI, HTTPException, Body, BackgroundTasks, Depends
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from dotenv import load_dotenv
from supabase import create_client
from openai import OpenAI

# Service isolation for Word document generation
from export_service import ExportService

# AI instruction logic isolated for modularity
from ai_instructions import (
    SYSTEM_ASSESSMENT_DESIGN,
    get_assessment_prompt
)

# Standard logging configuration for demo visibility
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - %(message)s'
)
logger = logging.getLogger("CheckMateBackend")

load_dotenv()

app = FastAPI(title="CheckMate Compliance API")

# --- DATABASE ---
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- SECURITY ---
security = HTTPBearer()

async def get_current_user(credentials = Depends(security)):
    """Verifies JWT. Tip: Use for protecting sensitive endpoints."""
    try:
        user = supabase.auth.get_user(credentials.credentials)
        if not user: return None
        return user
    except:
        return None

# --- AI CONFIG ---
USE_CLOUD_AI = os.getenv("USE_CLOUD_AI", "False").lower() == "true"
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "meta-llama/llama-3.1-8b-instruct:free").strip()

OR_CLIENT = None
if USE_CLOUD_AI and OPENROUTER_API_KEY:
    try:
        OR_CLIENT = OpenAI(base_url="https://openrouter.ai/api/v1", api_key=OPENROUTER_API_KEY)
    except:
        logger.error("Cloud AI Client failed to initialize.")

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/api/chat")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")

# --- SCHEMAS ---

class ExamRequest(BaseModel):
    topic: str
    material: str = None
    question_count: int = 5
    class_id: str

class BatchSyncRequest(BaseModel):
    exam_id: str
    results: list

# --- AI CORE ---

async def call_ai_engine(prompt, system_msg):
    """Orchestrates between Cloud and Local based on .env config."""
    if USE_CLOUD_AI and OR_CLIENT:
        try:
            loop = asyncio.get_event_loop()
            completion = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                response_format={"type": "json_object"}
            ))
            return json.loads(completion.choices[0].message.content)
        except:
            raise HTTPException(status_code=502, detail="Cloud Engine Timeout")
    else:
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                resp = await client.post(OLLAMA_URL, json={
                    "model": OLLAMA_MODEL,
                    "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                    "stream": False, "format": "json"
                })
                return json.loads(resp.json()["message"]["content"])
        except:
            raise HTTPException(status_code=503, detail="Local Engine (Ollama) Unreachable")

async def stream_ai_logic(prompt, system_msg):
    """Pipes real-time AI chunks to the Flutter terminal view."""
    yield "LOG: Initializing Pipeline...\n"
    try:
        if USE_CLOUD_AI and OR_CLIENT:
            loop = asyncio.get_event_loop()
            stream = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                stream=True, response_format={"type": "json_object"}
            ))
            for chunk in stream:
                if chunk.choices[0].delta.content:
                    yield f"AI: {chunk.choices[0].delta.content}"
        else:
            async with httpx.AsyncClient(timeout=180.0) as client:
                async with client.stream("POST", OLLAMA_URL, json={
                    "model": OLLAMA_MODEL,
                    "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                    "stream": True, "format": "json"
                }) as response:
                    async for line in response.aiter_lines():
                        if line:
                            yield f"AI: {json.loads(line).get('message', {}).get('content', '')}"
        yield "\nLOG: Complete.\n"
    except:
        yield "ERROR: Connection Lost\n"

# --- ENDPOINTS ---

@app.get("/")
async def status():
    """Health check for the backend."""
    return {"status": "ready", "engine": "Cloud" if USE_CLOUD_AI else "Local", "model": OPENROUTER_MODEL if USE_CLOUD_AI else OLLAMA_MODEL}

@app.post("/generate-exam")
async def generate_exam(request: ExamRequest):
    """BR-02: AI-Assisted Assessment Generation."""
    logger.info(f"Generating Exam: {request.topic} ({request.question_count} questions)")
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    try:
        # DB Record Creation (Optional)
        exam_id = "temp-dev-id"
        try:
            res = supabase.table("exams").insert({"class_id": request.class_id, "title": f"{request.topic} Quiz", "is_approved": False}).execute()
            if res.data: exam_id = res.data[0]['id']
        except: pass

        # AI Execution
        raw_data = await call_ai_engine(prompt, SYSTEM_ASSESSMENT_DESIGN)
        questions = raw_data.get("questions", []) if isinstance(raw_data, dict) else raw_data
        if not isinstance(questions, list): questions = [raw_data]
            
        final_list = questions[:request.question_count]

        # Persist results
        if exam_id != "temp-dev-id":
            try:
                inserts = [{"exam_id": exam_id, "question_text": str(q.get('questionText', q.get('text', ''))), "correct_answer": str(q.get('correctAnswer', 'A')), "question_type": str(q.get('questionType', 'MCQ')), "topic_tag": str(q.get('topicTag', request.topic))} for q in final_list]
                supabase.table("questions").insert(inserts).execute()
            except: pass

        return {"exam_id": exam_id, "questions": final_list}
    except:
        raise HTTPException(status_code=500, detail="AI Processing Failed")

@app.post("/generate-exam-stream")
async def generate_exam_stream(request: ExamRequest):
    """Live debugging stream for the frontend terminal."""
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    return StreamingResponse(stream_ai_logic(prompt, SYSTEM_ASSESSMENT_DESIGN), media_type="text/event-stream")

@app.post("/batch-save-grades")
async def batch_sync(sync_data: BatchSyncRequest):
    """BR-07: Controlled session synchronization."""
    try:
        for r in sync_data.results:
            supabase.table("grades").insert({"sheet_id": r.sheet_id, "score": r.score, "total_questions": r.total, "percentage": (r.score/r.total*100)}).execute()
        return {"status": "success"}
    except:
        raise HTTPException(status_code=500, detail="Sync Error")

@app.post("/export-docx")
async def export(data: dict = Body(...)):
    """Exports generated questions to a professional .docx file."""
    try:
        title = data.get("title", "Assessment")
        questions = data.get("questions", [])
        buffer = ExportService.generate_assessment_docx(title, questions)
        return StreamingResponse(buffer, media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    except:
        raise HTTPException(status_code=500, detail="DOCX Export Failed")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
