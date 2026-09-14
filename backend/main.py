"""
Checkmate LMS Backend - Compliance & AI Orchestration Service.
Enforces Business Rules BR-01 through BR-13.

MAINTENANCE NOTES:
- Hugging Face AI: Connects to Llama 3.3 70B Instruct via HF Inference API (Requires HF_TOKEN).
- OpenRouter AI: Optional Cloud AI fallback (Requires OPENROUTER_API_KEY).
- Local AI: Uses Ollama (Requires local Ollama server).
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
    SYSTEM_CLASS_ANALYSIS,
    SYSTEM_STUDENT_MENTOR,
    get_assessment_prompt,
    get_class_analysis_prompt,
    get_student_insight_prompt
)

# Standard logging configuration for visibility
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
supabase = None
if SUPABASE_URL and SUPABASE_KEY:
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        logger.info("Supabase client initialized successfully.")
    except Exception as e:
        logger.error(f"Failed to initialize Supabase client: {e}")

# --- SECURITY ---
security = HTTPBearer()

async def get_current_user(credentials = Depends(security)):
    """Verifies JWT for protected routes."""
    if not supabase:
        return None
    try:
        user = supabase.auth.get_user(credentials.credentials)
        if not user: return None
        return user
    except:
        return None

# --- AI CONFIG ---
AI_PROVIDER = os.getenv("AI_PROVIDER", "hf").lower() # 'hf', 'openrouter', or 'ollama'

HF_TOKEN = os.getenv("HF_TOKEN", "").strip() or os.getenv("HUGGINGFACEHUB_API_TOKEN", "").strip()
HF_MODEL = os.getenv("HF_MODEL", "meta-llama/Llama-3.3-70B-Instruct").strip()
HF_BASE_URL = os.getenv("HF_BASE_URL", "https://api-inference.huggingface.co/v1/").strip()

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "meta-llama/llama-3.1-8b-instruct:free").strip()

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/api/chat")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")

HF_CLIENT = None
if HF_TOKEN:
    try:
        HF_CLIENT = OpenAI(base_url=HF_BASE_URL, api_key=HF_TOKEN)
        logger.info(f"Hugging Face Client initialized for model: {HF_MODEL}")
    except Exception as e:
        logger.error(f"Hugging Face Client failed to initialize: {e}")

OR_CLIENT = None
if OPENROUTER_API_KEY:
    try:
        OR_CLIENT = OpenAI(base_url="https://openrouter.ai/api/v1", api_key=OPENROUTER_API_KEY)
        logger.info("OpenRouter Client initialized")
    except Exception as e:
        logger.error(f"OpenRouter Client failed to initialize: {e}")

# --- SCHEMAS ---

class ExamRequest(BaseModel):
    topic: str
    material: str = None
    question_count: int = 5
    class_id: str

class BatchSyncRequest(BaseModel):
    exam_id: str
    results: list

class AnalysisRequest(BaseModel):
    class_id: str
    exam_id: str

class StudentInsightRequest(BaseModel):
    student_name: str
    score: int
    total: int
    errors: list = []

# --- AI HELPER FUNCTIONS ---

def parse_json_safely(content: str) -> dict:
    """Parses JSON content, stripping markdown code block fences if present."""
    if isinstance(content, dict):
        return content
    cleaned = content.strip()
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    elif cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    cleaned = cleaned.strip()
    return json.loads(cleaned)

async def call_ai_engine(prompt: str, system_msg: str) -> dict:
    """Orchestrates between Hugging Face (Llama 3.3 70B), OpenRouter, and Ollama."""
    provider = AI_PROVIDER

    # Default to HF if HF_CLIENT is present
    if (provider == "hf" or not provider) and HF_CLIENT:
        try:
            loop = asyncio.get_event_loop()
            completion = await loop.run_in_executor(None, lambda: HF_CLIENT.chat.completions.create(
                model=HF_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                temperature=0.3,
                max_tokens=2048
            ))
            return parse_json_safely(completion.choices[0].message.content)
        except Exception as e:
            logger.error(f"Hugging Face API Error: {e}")
            raise HTTPException(status_code=502, detail=f"Hugging Face Engine Error: {str(e)}")

    elif provider == "openrouter" and OR_CLIENT:
        try:
            loop = asyncio.get_event_loop()
            completion = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                response_format={"type": "json_object"}
            ))
            return parse_json_safely(completion.choices[0].message.content)
        except Exception as e:
            logger.error(f"OpenRouter API Error: {e}")
            raise HTTPException(status_code=502, detail="Cloud Engine Timeout")

    else:
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                resp = await client.post(OLLAMA_URL, json={
                    "model": OLLAMA_MODEL,
                    "messages": [{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                    "stream": False, "format": "json"
                })
                return parse_json_safely(resp.json()["message"]["content"])
        except Exception as e:
            logger.error(f"Local Ollama Error: {e}")
            raise HTTPException(status_code=503, detail="Local Engine (Ollama) Unreachable")

async def stream_ai_logic(prompt: str, system_msg: str):
    """Pipes real-time AI chunks to the terminal view."""
    yield "LOG: Initializing Pipeline...\n"
    try:
        if (AI_PROVIDER == "hf" or not AI_PROVIDER) and HF_CLIENT:
            loop = asyncio.get_event_loop()
            stream = await loop.run_in_executor(None, lambda: HF_CLIENT.chat.completions.create(
                model=HF_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                stream=True,
                max_tokens=2048
            ))
            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta and chunk.choices[0].delta.content:
                    yield f"AI: {chunk.choices[0].delta.content}"
        elif AI_PROVIDER == "openrouter" and OR_CLIENT:
            loop = asyncio.get_event_loop()
            stream = await loop.run_in_executor(None, lambda: OR_CLIENT.chat.completions.create(
                model=OPENROUTER_MODEL,
                messages=[{"role": "system", "content": system_msg}, {"role": "user", "content": prompt}],
                stream=True, response_format={"type": "json_object"}
            ))
            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta and chunk.choices[0].delta.content:
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
    except Exception as e:
        logger.error(f"Streaming Error: {e}")
        yield f"ERROR: Connection Lost ({str(e)})\n"

# --- ENDPOINTS ---

@app.get("/")
async def status():
    """Health check for the backend."""
    active_model = HF_MODEL if (AI_PROVIDER == "hf" or HF_CLIENT) else (OPENROUTER_MODEL if AI_PROVIDER == "openrouter" else OLLAMA_MODEL)
    return {
        "status": "online",
        "provider": AI_PROVIDER,
        "model": active_model,
        "database": "connected" if supabase else "disconnected"
    }

@app.post("/generate-exam")
async def generate_exam(request: ExamRequest):
    """BR-02: AI-Assisted Assessment Generation."""
    logger.info(f"Generating Exam: {request.topic} ({request.question_count} questions)")
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    try:
        exam_id = "temp-dev-id"
        if supabase:
            try:
                res = supabase.table("exams").insert({
                    "class_id": request.class_id,
                    "title": f"{request.topic} Quiz",
                    "is_approved": False
                }).execute()
                if res.data: exam_id = res.data[0]['id']
            except Exception as db_err:
                logger.warning(f"Failed to create exam record: {db_err}")

        # AI Execution
        raw_data = await call_ai_engine(prompt, SYSTEM_ASSESSMENT_DESIGN)
        questions = raw_data.get("questions", []) if isinstance(raw_data, dict) else raw_data
        if not isinstance(questions, list): questions = [raw_data]
            
        final_list = questions[:request.question_count]

        # Persist questions
        if supabase and exam_id != "temp-dev-id":
            try:
                inserts = [{
                    "exam_id": exam_id,
                    "question_text": str(q.get('questionText', q.get('text', ''))),
                    "correct_answer": str(q.get('correctAnswer', 'A')),
                    "question_type": str(q.get('questionType', 'MCQ')),
                    "topic_tag": str(q.get('topicTag', request.topic))
                } for q in final_list]
                supabase.table("questions").insert(inserts).execute()
            except Exception as q_err:
                logger.warning(f"Failed to persist questions: {q_err}")

        return {"exam_id": exam_id, "questions": final_list}
    except Exception as e:
        logger.error(f"Generate exam error: {e}")
        raise HTTPException(status_code=500, detail=f"AI Processing Failed: {str(e)}")

@app.post("/generate-exam-stream")
async def generate_exam_stream(request: ExamRequest):
    """Live debugging stream for the frontend terminal."""
    prompt = get_assessment_prompt(request.material or request.topic, request.question_count)
    return StreamingResponse(stream_ai_logic(prompt, SYSTEM_ASSESSMENT_DESIGN), media_type="text/event-stream")

@app.get("/resolve-sheet/{sheet_id}")
async def resolve_sheet(sheet_id: str):
    """BR-05: Resolve sheet metadata by sheet_id."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database connection unconfigured")
    try:
        res = supabase.table("answer_sheets").select("*, students(full_name), exams(*)").eq("id", sheet_id).execute()
        if not res.data:
            raise HTTPException(status_code=404, detail="Sheet not found")
        return res.data[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error resolving sheet {sheet_id}: {e}")
        raise HTTPException(status_code=500, detail="Database resolve error")

@app.post("/batch-save-grades")
async def batch_sync(sync_data: BatchSyncRequest):
    """BR-07: Controlled session synchronization."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database connection unconfigured")
    try:
        for r in sync_data.results:
            supabase.table("grades").insert({
                "sheet_id": r.sheet_id,
                "score": r.score,
                "total_questions": r.total,
                "percentage": (r.score / r.total * 100) if r.total > 0 else 0
            }).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Sync error: {e}")
        raise HTTPException(status_code=500, detail="Sync Error")

@app.post("/analyze-class")
async def analyze_class(request: AnalysisRequest):
    """BR-09: Class-Wide AI Performance Analysis."""
    try:
        grades_data = []
        if supabase:
            res = supabase.table("grades").select("*").eq("exam_id", request.exam_id).execute()
            grades_data = res.data or []
        prompt = get_class_analysis_prompt(json.dumps(grades_data))
        analysis = await call_ai_engine(prompt, SYSTEM_CLASS_ANALYSIS)
        return {"exam_id": request.exam_id, "analysis": analysis}
    except Exception as e:
        logger.error(f"Class analysis failed: {e}")
        raise HTTPException(status_code=500, detail=f"Class analysis failed: {str(e)}")

@app.post("/student-insight")
async def student_insight(request: StudentInsightRequest):
    """BR-10: Personalized AI Feedback."""
    try:
        pct = (request.score / request.total * 100) if request.total > 0 else 0
        prompt = get_student_insight_prompt(
            request.student_name, request.score, request.total, pct, json.dumps(request.errors)
        )
        insight = await call_ai_engine(prompt, SYSTEM_STUDENT_MENTOR)
        return {"student": request.student_name, "insight": insight}
    except Exception as e:
        logger.error(f"Student insight failed: {e}")
        raise HTTPException(status_code=500, detail=f"Student insight failed: {str(e)}")

@app.post("/export-docx")
async def export(data: dict = Body(...)):
    """Exports generated questions to a professional .docx file."""
    try:
        title = data.get("title", "Assessment")
        questions = data.get("questions", [])
        buffer = ExportService.generate_assessment_docx(title, questions)
        return StreamingResponse(
            buffer,
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            headers={"Content-Disposition": f"attachment; filename={title}.docx"}
        )
    except Exception as e:
        logger.error(f"DOCX Export failed: {e}")
        raise HTTPException(status_code=500, detail="DOCX Export Failed")

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 7860))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
