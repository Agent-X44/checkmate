"""
Checkmate LMS Backend - Compliance & AI Orchestration Service.
Enforces Business Rules BR-01 through BR-13.
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

# Custom service for handling Word document creation
from export_service import ExportService

# Structured AI prompts and configurations
from ai_instructions import (
    SYSTEM_ASSESSMENT_DESIGN,
    get_assessment_prompt
)

# Initialize standard Python logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("CheckmateBackend")

# Load environment configuration
load_dotenv()

app = FastAPI(title="Checkmate LMS Compliance API")

# --- DATABASE INITIALIZATION ---
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- SECURITY ---
security = HTTPBearer()

async def get_current_user(credentials = Depends(security)):
    """Verifies Supabase JWT and returns user data."""
    try:
        user = supabase.auth.get_user(credentials.credentials)
        if not user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user
    except:
        raise HTTPException(status_code=401, detail="Unauthorized access")

# --- AI ENGINE CONFIGURATION ---
USE_CLOUD_AI = os.getenv("USE_CLOUD_AI", "False").lower() == "true"

# Cloud AI Settings (OpenRouter)
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "meta-llama/llama-3.1-8b-instruct:free").strip()

# Local AI Settings (Ollama)
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/api/chat")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")

# Initialize OpenRouter client if Cloud mode is enabled
OR_CLIENT = None
if USE_CLOUD_AI and OPENROUTER_API_KEY:
    try:
        OR_CLIENT = OpenAI(
            base_url="https://openrouter.ai/api/v1",
            api_key=OPENROUTER_API_KEY,
        )
        logger.info("AI ENGINE: Cloud Mode Active")
    except:
        logger.error("Cloud Engine Failed to Start")

if not USE_CLOUD_AI:
    logger.info("AI ENGINE: Local Mode Active")

# --- DATA SCHEMAS ---

class ExamRequest(BaseModel):
    topic: str
    material: str = None
    question_count: int = 5
    class_id: str

class StudentResult(BaseModel):
    sheet_id: str
    student_id: str
    score: int
    total: int

class BatchSyncRequest(BaseModel):
    exam_id: str
    results: list

# --- UTILITY FUNCTIONS ---

def is_valid_uuid(val):
    """Checks if a string is a valid UUID."""
    try:
        uuid.UUID(str(val))
        return True
    except:
        return False

# --- AI CORE ORCHESTRATION ---

async def call_ai_engine(prompt, system_msg):
    """Mediator that directs AI requests to the active engine."""
    if USE_CLOUD_AI and OR_CLIENT:
        try:
            loop = asyncio.get_event_loop()
            completion = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[
                    {"role": "system", "content": system_msg},
                    {"role": "user", "content": prompt}
                ],
                response_format={"type": "json_object"}
            ))
            return json.loads(completion.choices[0].message.content)
        except:
            raise HTTPException(status_code=502, detail="Cloud AI Error")
    else:
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                resp = await client.post(OLLAMA_URL, json={
                    "model": OLLAMA_MODEL,
                    "messages": [
                        {"role": "system", "content": system_msg},
                        {"role": "user", "content": prompt}
                    ],
                    "stream": False,
                    "format": "json"
                })
                resp.raise_for_status()
                return json.loads(resp.json()["message"]["content"])
        except:
            raise HTTPException(status_code=503, detail="Local AI Error")

async def stream_ai_logic(prompt, system_msg):
    """Asynchronous generator for live 'Terminal' debugging."""
    yield "LOG: Initializing AI Stream...\n"
    try:
        if USE_CLOUD_AI and OR_CLIENT:
            loop = asyncio.get_event_loop()
            stream = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[
                    {"role": "system", "content": system_msg},
                    {"role": "user", "content": prompt}
                ],
                stream=True,
                response_format={"type": "json_object"}
            ))
            for chunk in stream:
                content = chunk.choices[0].delta.content
                if content:
                    yield f"AI: {content}"
        else:
            async with httpx.AsyncClient(timeout=180.0) as client:
                async with client.stream("POST", OLLAMA_URL, json={
                    "model": OLLAMA_MODEL,
                    "messages": [
                        {"role": "system", "content": system_msg},
                        {"role": "user", "content": prompt}
                    ],
                    "stream": True,
                    "format": "json"
                }) as response:
                    async for line in response.aiter_lines():
                        if line:
                            content = json.loads(line).get('message', {}).get('content', '')
                            yield f"AI: {content}"
        yield "\nLOG: AI Generation Complete.\n"
    except:
        yield "ERROR: Stream Interrupted\n"

# --- API ENDPOINTS ---

@app.get("/")
async def health_check():
    return {"status": "online", "engine": OLLAMA_MODEL if not USE_CLOUD_AI else OPENROUTER_MODEL}

@app.post("/generate-exam")
async def generate_exam(request: ExamRequest):
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    try:
        exam_id = "temp-dev-id"
        if is_valid_uuid(request.class_id):
            try:
                res = supabase.table("exams").insert({
                    "class_id": request.class_id, 
                    "title": f"{request.topic} Quiz", 
                    "is_approved": False
                }).execute()
                if res.data: 
                    exam_id = res.data[0]['id']
            except:
                pass

        raw_data = await call_ai_engine(prompt, SYSTEM_ASSESSMENT_DESIGN)
        
        questions = raw_data.get("questions", []) if isinstance(raw_data, dict) else raw_data
        if not isinstance(questions, list):
            questions = [raw_data]
            
        final_list = questions[:request.question_count]

        if exam_id != "temp-dev-id" and final_list:
            try:
                inserts = [{
                    "exam_id": exam_id, 
                    "question_text": str(q.get('questionText', q.get('text', ''))), 
                    "correct_answer": str(q.get('correctAnswer', 'A')),
                    "question_type": str(q.get('questionType', 'MCQ')),
                    "topic_tag": str(q.get('topicTag', request.topic))
                } for q in final_list]
                supabase.table("questions").insert(inserts).execute()
            except:
                pass

        return {"exam_id": exam_id, "questions": final_list}
    except:
        raise HTTPException(status_code=500, detail="Generation Failed")

@app.post("/generate-exam-stream")
async def generate_exam_stream(request: ExamRequest):
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    return StreamingResponse(
        stream_ai_logic(prompt, SYSTEM_ASSESSMENT_DESIGN), 
        media_type="text/event-stream"
    )

@app.post("/batch-save-grades")
async def batch_save_grades(sync_data: BatchSyncRequest):
    try:
        for r in sync_data.results:
            supabase.table("grades").insert({
                "sheet_id": r.sheet_id, 
                "score": r.score, 
                "total_questions": r.total, 
                "percentage": (r.score/r.total*100) if r.total > 0 else 0
            }).execute()
        return {"status": "success"}
    except:
        raise HTTPException(status_code=500, detail="Database Sync Error")

@app.post("/export-docx")
async def export_docx(data: dict = Body(...)):
    try:
        title = data.get("title", "Assessment")
        questions = data.get("questions", [])
        doc_buffer = ExportService.generate_assessment_docx(title, questions)
        return StreamingResponse(
            doc_buffer,
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )
    except:
        raise HTTPException(status_code=500, detail="Export Error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
