"""
Checkmate LMS Backend - Compliance & AI Orchestration Service.
Enforces Business Rules BR-01 through BR-13.

MAINTENANCE NOTES:
- Hugging Face AI: Connects to Llama 3.3 70B Instruct via HF Inference API (Requires HF_TOKEN).
- OpenRouter AI: Optional Cloud AI fallback (Requires OPENROUTER_API_KEY).
- Local AI: Uses Ollama (Requires local Ollama server).
- Security: Protected routes require Supabase JWT.
"""

import asyncio
import asyncio
import os
import json
import logging
import uuid
import re
from io import BytesIO
from fastapi import FastAPI, HTTPException, Body, Depends, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer
from pydantic import BaseModel, Field
from dotenv import load_dotenv
from supabase import create_client
import PyPDF2
from docx import Document
import pptx

# Service isolation for Word document generation
from export_service import ExportService

# AI Service and instructions
from ai_service import (
    generate_structured_response,
    AssessmentResponse,
    ClassAnalysisResponse,
    StudentInsightResponse,
    StudentOverviewResponse,
    HF_MODEL_FAST,
    HF_MODEL_REASONING,
    client as hf_client,
    parse_json_safely
)
from result_analysis import class_summary, enrich_answers, grade_context, question_counts, student_summary, student_overview_summary, topic_counts
from ai_instructions import (
    SYSTEM_ASSESSMENT_DESIGN,
    SYSTEM_CLASS_ANALYSIS,
    SYSTEM_STUDENT_MENTOR,
    get_assessment_prompt,
    get_existing_questions_prompt,
    get_class_analysis_prompt,
    get_student_insight_prompt
)

def select_template(mcq_count: int, tf_count: int) -> str:
    total = mcq_count + tf_count
    if total <= 30:
        if tf_count == 0:
            return "standard_30_questions"
        else:
            return "mixed_15mcq_15tf"
    else:
        if tf_count == 0:
            return "standard_50_questions"
        elif mcq_count == 25 and tf_count == 25:
            return "mixed_25mcq_25tf"
        elif mcq_count == 20 and tf_count == 30:
            return "mixed_20mcq_30tf"
        elif mcq_count == 30 and tf_count == 20:
            return "mixed_30mcq_20tf"
        else:
            return "standard_50_questions"

# Standard logging configuration for visibility
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - %(message)s'
)
logger = logging.getLogger("CheckMateBackend")

load_dotenv()

app = FastAPI(title="CheckMate Compliance API")

active_generations = set()
background_tasks_refs = set()

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

import httpx
import re

def extract_text_from_file(file: UploadFile, content_bytes: bytes) -> str:
    """Extracts raw text from PDF, DOCX, PPTX, or TXT files."""
    filename = file.filename.lower()
    text = ""
    try:
        if filename.endswith(".pdf"):
            reader = PyPDF2.PdfReader(BytesIO(content_bytes))
            for page in reader.pages:
                page_text = page.extract_text()
                if page_text:
                    text += page_text + "\n"
        elif filename.endswith(".docx"):
            doc = Document(BytesIO(content_bytes))
            for p in doc.paragraphs:
                text += p.text + "\n"
        elif filename.endswith(".pptx"):
            prs = pptx.Presentation(BytesIO(content_bytes))
            for slide in prs.slides:
                for shape in slide.shapes:
                    if hasattr(shape, "text"):
                        text += shape.text + "\n"
        else: # Fallback to utf-8 text
            text = content_bytes.decode('utf-8', errors='ignore')
    except Exception as e:
        logger.warning(f"File extraction error for {filename}: {e}")
        text = content_bytes.decode('utf-8', errors='ignore')
    
    # Truncate text if it's too massively large (to save tokens)
    return text[:20000]

def parse_plaintext_questions(text: str, default_topic: str) -> list[dict]:
    """Parses plain text stream into structured question dicts instantly with 0 latency."""
    blocks = re.split(r'\n(?=\d+\.\s+)', text.strip())
    questions = []
    
    for block in blocks:
        block = block.strip()
        if not block:
            continue
            
        lines = [l.strip() for l in block.split('\n') if l.strip()]
        if not lines:
            continue
            
        q_text = ""
        options = []
        correct_answer = "A"
        
        for line in lines:
            clean_line = re.sub(r'^\d+\.\s*', '', line)
            opt_match = re.match(r'^[A-Da-d][\.\)]\s+(.*)', clean_line)
            # Answer pattern can be "ANSWER: B" or "ANSWER: T"
            ans_match = re.search(r'ANSWER:\s*([A-Da-dTtFf])', clean_line, re.IGNORECASE)
            
            if opt_match:
                options.append(opt_match.group(1).strip())
            elif ans_match:
                correct_answer = ans_match.group(1).upper()
            else:
                if not options and not ans_match:
                    if q_text:
                        q_text += " " + clean_line
                    else:
                        q_text = clean_line

        if q_text:
            is_tf = False
            
            # Smart TF Detection: If the answer is T/F, or there are no options, or the first two options are True/False
            if correct_answer in ['T', 'F'] or len(options) == 0:
                is_tf = True
            elif len(options) >= 2:
                opt_a = options[0].strip().lower()
                opt_b = options[1].strip().lower()
                if ('true' in opt_a and 'false' in opt_b) or ('false' in opt_a and 'true' in opt_b):
                    is_tf = True

            if is_tf:
                # Map T->A (True) and F->B (False)
                mapped_answer = "A" if correct_answer in ['T', 'A'] else "B"
                questions.append({
                    "part": 2,
                    "questionType": "TF",
                    "questionText": q_text,
                    "options": ["True", "False"],
                    "correctAnswer": mapped_answer,
                    "topicTag": default_topic
                })
            elif len(options) >= 2:
                # We do NOT append options to questionText anymore to avoid duplicating them in the UI and DOCX
                questions.append({
                    "part": 1,
                    "questionType": "MCQ",
                    "questionText": q_text,
                    "options": options,
                    "correctAnswer": correct_answer if correct_answer in ['A', 'B', 'C', 'D'] else 'A',
                    "topicTag": default_topic
                })
            
    return questions

def select_template(mcq_count: int, tf_count: int) -> str:
    total = mcq_count + tf_count
    if mcq_count == 15 and tf_count == 15:
        return "mixed_30_15mcq_15tf_v1"
    elif mcq_count == 25 and tf_count == 25:
        return "mixed_50_25mcq_25tf_v1"
    elif mcq_count == 20 and tf_count == 30:
        return "mixed_50_20mcq_30tf_v1"
    elif mcq_count == 30 and tf_count == 20:
        return "mixed_50_30mcq_20tf_v1"
    elif total <= 30 and tf_count == 0:
        return "standard_30_questions" # Using the flutter class name or a new id
    elif total <= 50 and tf_count == 0:
        return "standard_50_v1"
    # fallback
    return "standard_50_v1"

async def stream_openrouter_raw(
    prompt: str,
    system_msg: str,
    max_tokens: int = 10000,
    model_override: str | None = None,
):
    """Raw httpx streaming generator for OpenRouter to prevent SDK buffering."""
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/checkmate-lms",
        "X-Title": "CheckMate LMS"
    }
    payload = {
        "model": model_override or HF_MODEL_FAST,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.3,
        "max_tokens": max_tokens,
        "stream": True
    }
    
    async with httpx.AsyncClient(timeout=180.0) as client:
        async with client.stream("POST", "https://openrouter.ai/api/v1/chat/completions", json=payload, headers=headers) as response:
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data_str = line[6:].strip()
                    if data_str == "[DONE]":
                        break
                    try:
                        data_json = json.loads(data_str)
                        delta = data_json.get("choices", [{}])[0].get("delta", {}).get("content", "")
                        if delta:
                            yield delta
                    except Exception:
                        pass

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()

AI_PROVIDER = "openrouter"

# Default to 70B for complex reasoning tasks (Analysis/Insights)
HF_MODEL_REASONING = os.getenv("OPENROUTER_MODEL_REASONING", "meta-llama/llama-3.3-70b-instruct").strip()
# Default to 8B for fast, structured generation tasks (Exams)
HF_MODEL_FAST = os.getenv("OPENROUTER_MODEL_FAST", "meta-llama/llama-3.1-8b-instruct").strip()

if OPENROUTER_API_KEY:
    logger.info(f"AI Client configured. Fast model: {HF_MODEL_FAST}, Reasoning model: {HF_MODEL_REASONING}")
else:
    logger.warning("AI Client failed to initialize. API Key is missing.")

# --- SCHEMAS ---

class ExamRequest(BaseModel):
    topic: str
    material: str = None
    question_count: int = Field(default=5, le=50, description="Maximum of 50 questions per request")
    class_id: str
    assessment_type: str = "Quiz"
    include_mcq: bool = True
    include_tf: bool = True
    mcq_count: int = 5
    tf_count: int = 0

class SaveDraftRequest(BaseModel):
    class_id: str
    title: str
    assessment_type: str = "Quiz"
    questions: list
    template_id: str | None = None
    has_multiple_sets: bool = False

class SyncResultItem(BaseModel):
    sheet_id: str
    score: int
    total: int
    answers: list[dict] = Field(default_factory=list)

class BatchSyncRequest(BaseModel):
    exam_id: str
    results: list[SyncResultItem]

class AnalysisRequest(BaseModel):
    exam_id: str
    class_id: str | None = None

class StudentInsightRequest(BaseModel):
    exam_id: str
    sheet_id: str
    regenerate: bool = False

# --- AI HELPER FUNCTIONS ---

async def stream_ai_logic(prompt: str, system_msg: str):
    """Debug-only streaming path using raw httpx to prevent SDK buffering."""
    yield "LOG: Initializing Pipeline...\n\n"
    try:
        async for chunk in stream_openrouter_raw(prompt, system_msg):
            yield chunk
        yield "\n\nLOG: Complete.\n"
    except Exception as e:
        logger.error(f"Streaming Error: {e}")
        yield f"\nERROR: Connection Lost ({str(e)})\n"

# --- ENDPOINTS ---

@app.get("/")
async def status():
    """Health check for the backend."""
    active_model = HF_MODEL_FAST if hf_client else "offline"
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
        template_id = select_template(request.mcq_count, request.tf_count)
        
        try:
            uuid.UUID(str(request.class_id))
            if supabase:
                try:
                    res = supabase.table("exams").insert({
                        "class_id": request.class_id,
                        "title": f"[{request.assessment_type}] {request.topic}",
                        "is_approved": False,
                        "template_id": template_id,
                        "total_questions": request.question_count,
                        "mcq_count": request.mcq_count,
                        "tf_count": request.tf_count,
                    }).execute()
                    if res.data: exam_id = res.data[0]['id']
                except Exception as db_err:
                    logger.warning(f"Failed to create exam record: {db_err}")
        except (ValueError, TypeError, AttributeError):
            logger.warning(f"Skipping DB insert for invalid class_id: {request.class_id!r}")

        # AI Execution
        structured_response = await generate_structured_response(
            system_prompt=SYSTEM_ASSESSMENT_DESIGN,
            user_prompt=prompt,
            schema_class=AssessmentResponse,
            model_override=HF_MODEL_FAST
        )
        
        final_list = [q.model_dump() for q in structured_response.questions[:request.question_count]]

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
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Generate exam error: {e}")
        raise HTTPException(status_code=500, detail=f"AI Processing Failed: {str(e)}")

@app.post("/generate-exam-stream")
async def generate_exam_stream(
    topic: str = Form(...),
    class_id: str = Form(...),
    question_count: int = Form(5),
    assessment_type: str = Form('Quiz'),
    include_mcq: bool = Form(True),
    include_tf: bool = Form(True),
    mcq_count: int = Form(5),
    tf_count: int = Form(0),
    source_mode: str = Form("topic"),
    has_multiple_sets: bool = Form(False),
    file: UploadFile | None = File(None),
    background_tasks: BackgroundTasks = BackgroundTasks(),
):
    """Plain-text streaming with optional File Upload."""
    if question_count < 1 or question_count > 50:
        raise HTTPException(status_code=422, detail="question_count must be between 1 and 50.")
    
    task_key = f"{class_id}_{topic}_{assessment_type}_{source_mode}"
    if task_key in active_generations:
        async def duplicate_generator():
            yield f"data: {json.dumps({'type': 'error', 'content': 'The AI is already generating this exam in the background. Please check your Drafts in a minute.'})}\n\n"
        return StreamingResponse(duplicate_generator(), media_type="text/event-stream")

    # Read file synchronously to keep bytes in memory (prevents disconnect closure issues)
    filename = file.filename if file else None
    content_bytes = await file.read() if file else None
    if content_bytes and len(content_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Uploaded files must be 10 MB or smaller.")

    queue = asyncio.Queue()

    async def generation_worker():
        active_generations.add(task_key)
        try:
            material_text = topic
            if filename:
                opening_message = f"LOG: Uploading {filename}...\n"
                await queue.put(f"data: {json.dumps({'type': 'token', 'content': opening_message})}\n\n")
                
                await queue.put(f"data: {json.dumps({'type': 'token', 'content': 'LOG: Decoding file...' + chr(10)})}\n\n")
                class MockUploadFile:
                    def __init__(self, name):
                        self.filename = name
                    def read(self):
                        pass
                extracted = extract_text_from_file(MockUploadFile(filename), content_bytes) # type: ignore
                if extracted.strip():
                    material_text = f"Context from file '{filename}':\n{extracted}\n\nAdditional Topic info: {topic}"
                await queue.put(f"data: {json.dumps({'type': 'token', 'content': 'LOG: Formulating...' + chr(10)})}\n\n")
            else:
                await queue.put(f"data: {json.dumps({'type': 'token', 'content': 'LOG: Preparing topic for question generation...' + chr(10)})}\n\n")

            logger.info(f"Streaming Exam (Plain Text): {topic} ({question_count} questions)")
            
            prompt = (
                get_existing_questions_prompt(material_text, question_count)
                if source_mode == "existing_questions"
                else get_assessment_prompt(material_text, question_count, include_mcq, include_tf, mcq_count, tf_count, source_mode)
            )

            try:
                template_id = select_template(mcq_count, tf_count)
            except Exception:
                template_id = "standard_50_questions"

            exam_id = "temp-dev-id"
            if supabase:
                try:
                    res = supabase.table("exams").insert({
                        "class_id": class_id,
                        "title": f"[{assessment_type}] {topic}",
                        "is_approved": False,
                        "template_id": template_id,
                        "has_multiple_sets": has_multiple_sets,
                        "total_questions": question_count,
                        "mcq_count": mcq_count,
                        "tf_count": tf_count,
                    }).execute()
                    if res.data: exam_id = res.data[0]['id']
                except Exception as db_err:
                    logger.warning(f"Failed to create exam record: {db_err}")

            payload_init = json.dumps({'type': 'token', 'content': 'LOG: Generating...\n\n'})
            await queue.put(f"data: {payload_init}\n\n")
            
            try:
                structure_rule = ""
                if source_mode == "existing_questions":
                    structure_rule = "Preserve the supplied questions and answer keys. Do not create unrelated questions.\n\n"
                elif mcq_count > 0 and tf_count > 0:
                    structure_rule = (
                        "CRITICAL STRUCTURE RULE: You MUST divide your output into two separate parts.\n"
                        f"First, generate EXACTLY {mcq_count} Multiple Choice questions.\n"
                        f"Then, generate EXACTLY {tf_count} True/False questions.\n"
                        "Do NOT alternate them. Finish all MCQs before starting the True/False questions. Continue numbering consecutively.\n\n"
                    )
                elif mcq_count > 0:
                    structure_rule = f"Generate EXACTLY {mcq_count} Multiple Choice questions.\n\n"
                elif tf_count > 0:
                    structure_rule = f"Generate EXACTLY {tf_count} True/False questions.\n\n"

                system_msg = (
                    "You are an expert AI assessment generator.\n"
                    f"{structure_rule}"
                    "You must format EVERY Multiple Choice question strictly like this in clean plain text:\n"
                    "1. [Question text here?]\n"
                    "A. [First option]\n"
                    "B. [Second option]\n"
                    "C. [Third option]\n"
                    "D. [Fourth option]\n"
                    "ANSWER: [A, B, C, or D]\n\n"
                    "For True/False questions, format them strictly like this (do NOT write options A and B):\n"
                    "1. [True or False statement here.]\n"
                    "ANSWER: [T or F]\n\n"
                    "CRITICAL RULE: DO NOT write intro text like 'Here are the questions'. Start immediately with '1.'.\n"
                    "CRITICAL RULE: Your answer key MUST be 100% accurate and factually correct. Verify all logic, math, or assembly concepts step-by-step before assigning the correct letter.\n"
                    "CRITICAL RULE: Ensure ALL questions are entirely UNIQUE. DO NOT duplicate or repeat the same question twice.\n"
                    "You MUST randomize the correct answers across the exam. Mix them up randomly!"
                )

                full_text = ""
                async for content in stream_openrouter_raw(
                    prompt,
                    system_msg,
                    max_tokens=10000,
                    model_override=(
                        HF_MODEL_REASONING
                        if filename is not None or source_mode == "existing_questions"
                        else HF_MODEL_FAST
                    ),
                ):
                    full_text += content
                    payload_token = json.dumps({'type': 'token', 'content': content})
                    await queue.put(f"data: {payload_token}\n\n")
                
                payload_parsing = json.dumps({'type': 'token', 'content': '\n\nLOG: Instantly Parsing & Saving to Database...\n'})
                await queue.put(f"data: {payload_parsing}\n\n")
                
                parsed_questions = parse_plaintext_questions(full_text, topic)
                
                if not parsed_questions:
                    parsed_questions = [{
                        "part": 1,
                        "questionType": "MCQ",
                        "questionText": f"General question regarding {topic}?",
                        "options": ["Option A", "Option B", "Option C", "Option D"],
                        "correctAnswer": "A",
                        "topicTag": topic
                    }]

                final_list = parsed_questions[:question_count]

                if supabase and exam_id != "temp-dev-id":
                    try:
                        inserts = []
                        for q in final_list:
                            q_text = str(q.get('questionText', ''))
                            options = q.get('options', [])
                            
                            if q.get('questionType') == 'MCQ' and options:
                                formatted_options = "\n".join([f"{chr(65+i)}. {opt}" for i, opt in enumerate(options)])
                                q_text = f"{q_text}\n{formatted_options}"
                                
                            inserts.append({
                                "exam_id": exam_id,
                                "question_text": q_text,
                                "correct_answer": str(q.get('correctAnswer', 'A')),
                                "question_type": str(q.get('questionType', 'MCQ')),
                                "topic_tag": str(q.get('topicTag', topic))
                            })
                        supabase.table("questions").insert(inserts).execute()
                    except Exception as q_err:
                        logger.warning(f"Failed to persist questions: {q_err}")

                payload_complete = json.dumps({'type': 'complete', 'exam_id': exam_id, 'questions': final_list})
                await queue.put(f"data: {payload_complete}\n\n")

            except Exception as e:
                logger.error(f"Streaming Error: {e}")
                payload_exception = json.dumps({'type': 'error', 'content': str(e)})
                await queue.put(f"data: {payload_exception}\n\n")

        except Exception as e:
            logger.error(f"Generation worker error: {e}")
            await queue.put(f"data: {json.dumps({'type': 'error', 'content': str(e)})}\n\n")
        finally:
            active_generations.discard(task_key)
            await queue.put(None)

    task = asyncio.create_task(generation_worker())
    background_tasks_refs.add(task)
    task.add_done_callback(background_tasks_refs.discard)

    async def event_generator():
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                yield item
        except Exception:
            logger.info(f"Client disconnected for {task_key}. Background generation continues.")

    return StreamingResponse(event_generator(), media_type="text/event-stream")

@app.post("/save-draft")
async def save_draft(request: SaveDraftRequest):
    """Bypasses RLS restrictions for saving draft assessments."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        mcq_count = sum(1 for q in request.questions if q.get('questionType') == 'MCQ')
        tf_count = sum(1 for q in request.questions if q.get('questionType') == 'TF')
        template_id = request.template_id or select_template(mcq_count, tf_count)

        # 1. Insert Exam into Supabase
        res = supabase.table("exams").insert({
            "class_id": request.class_id,
            "title": f"[{request.assessment_type}] {request.title}",
            "is_approved": False,
            "status": "Draft",
            "template_id": template_id,
            "has_multiple_sets": request.has_multiple_sets,
            "total_questions": len(request.questions),
            "mcq_count": mcq_count,
            "tf_count": tf_count,
        }).execute()
        
        if not res.data:
            raise HTTPException(status_code=500, detail="Failed to insert exam record")
            
        exam_id = res.data[0]['id']
        
        # 2. Insert Questions into Supabase
        if request.questions:
            inserts = [{
                "exam_id": exam_id,
                "question_text": str(q.get('questionText', q.get('text', ''))),
                "correct_answer": str(q.get('correctAnswer', 'A')),
                "question_type": str(q.get('questionType', 'MCQ')),
                "topic_tag": str(q.get('topicTag', request.title))
            } for q in request.questions]
            supabase.table("questions").insert(inserts).execute()
            
        return {"status": "success", "exam_id": exam_id}
    except Exception as e:
        logger.error(f"Save draft error: {e}")
        raise HTTPException(status_code=500, detail=f"Database save error: {str(e)}")

@app.get("/get-exam-questions/{exam_id}")
async def get_exam_questions(exam_id: str, user=Depends(get_current_user)):
    """Fetch all questions for an exam bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    _instructor_exam(exam_id, user)
    try:
        # Order by question sequence/id to ensure correct order
        res = supabase.table("questions").select("*").eq("exam_id", exam_id).order("id").execute()
        return res.data or []
    except Exception as e:
        logger.error(f"Get exam questions error: {e}")
        raise HTTPException(status_code=500, detail=f"Database query error: {str(e)}")

class QuestionUpdatePayload(BaseModel):
    question_text: str
    options: list[str]
    correct_answer: str

@app.put("/update-question/{question_id}")
async def update_question(question_id: str, payload: QuestionUpdatePayload):
    """Update a specific question in an exam."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        res = supabase.table("questions").update({
            "question_text": payload.question_text,
            "options": payload.options,
            "correct_answer": payload.correct_answer
        }).eq("id", question_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Update question error: {e}")
        raise HTTPException(status_code=500, detail=f"Database update error: {str(e)}")

@app.delete("/delete-exam/{exam_id}")
async def delete_exam_endpoint(exam_id: str):
    """Delete an exam and its questions bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        supabase.table("ai_insights").delete().eq("exam_id", exam_id).execute()
        
        sheet_res = supabase.table("answer_sheets").select("id").eq("exam_id", exam_id).execute()
        sheet_ids = [s['id'] for s in (sheet_res.data or [])]
        for s_id in sheet_ids:
            supabase.table("grades").delete().eq("sheet_id", s_id).execute()
        supabase.table("answer_sheets").delete().eq("exam_id", exam_id).execute()
        
        supabase.table("questions").delete().eq("exam_id", exam_id).execute()
        supabase.table("exams").delete().eq("id", exam_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Delete exam error: {e}")
        raise HTTPException(status_code=500, detail=f"Delete exam error: {str(e)}")

@app.get("/get-exams/{class_id}")
async def get_exams(class_id: str):
    """Fetch all exams (including unapproved drafts) for a class bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        res = supabase.table("exams").select("*, questions(id, question_type), answer_sheets(id, grades(percentage))").eq("class_id", class_id).order("created_at", desc=True).execute()
        return res.data or []
    except Exception as e:
        logger.error(f"Get exams error: {e}")
        raise HTTPException(status_code=500, detail=f"Database query error: {str(e)}")

@app.post("/approve-exam/{exam_id}")
async def approve_exam(exam_id: str):
    """Approve an exam, locking content and marking it Ready bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        res = supabase.table("exams").update({
            "is_approved": True,
            "status": "Ready"
        }).eq("id", exam_id).execute()
        
        if not res.data:
            raise HTTPException(status_code=404, detail="Exam not found")
        return {"status": "success", "exam_id": exam_id, "is_approved": True}
    except Exception as e:
        logger.error(f"Approve exam error: {e}")
        raise HTTPException(status_code=500, detail=f"Approve exam error: {str(e)}")

@app.post("/unapprove-exam/{exam_id}")
async def unapprove_exam(exam_id: str):
    """Unapprove an exam so it returns to Draft status."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        res = supabase.table("exams").update({
            "is_approved": False,
            "status": "Draft"
        }).eq("id", exam_id).execute()
        
        if not res.data:
            raise HTTPException(status_code=404, detail="Exam not found")
        return {"status": "success", "exam_id": exam_id, "is_approved": False}
    except Exception as e:
        logger.error(f"Unapprove exam error: {e}")
        raise HTTPException(status_code=500, detail=f"Unapprove exam error: {str(e)}")

@app.post("/release-results/{exam_id}")
async def release_results(exam_id: str, user=Depends(get_current_user)):
    """Release assessment results to students bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    _instructor_exam(exam_id, user)
    try:
        res = supabase.table("exams").update({
            "results_released": True,
            "status": "Published"
        }).eq("id", exam_id).execute()
        
        if not res.data:
            raise HTTPException(status_code=404, detail="Exam not found")
        return {"status": "success", "exam_id": exam_id, "results_released": True}
    except Exception as e:
        logger.error(f"Release results error: {e}")
        raise HTTPException(status_code=500, detail=f"Release results error: {str(e)}")

@app.delete("/delete-course/{class_id}")
async def delete_course(class_id: str):
    """Admin/Backend cascade deletion of a course bypassing RLS and foreign keys."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    try:
        # Get exams
        exam_res = supabase.table("exams").select("id").eq("class_id", class_id).execute()
        exam_ids = [e['id'] for e in (exam_res.data or [])]
        
        for exam_id in exam_ids:
            try:
                supabase.table("ai_insights").delete().eq("exam_id", exam_id).execute()
            except Exception as e:
                logger.warning(f"ai_insights delete notice: {e}")
            
            try:
                sheet_res = supabase.table("answer_sheets").select("id").eq("exam_id", exam_id).execute()
                sheet_ids = [s['id'] for s in (sheet_res.data or [])]
                for s_id in sheet_ids:
                    try:
                        supabase.table("grades").delete().eq("sheet_id", s_id).execute()
                    except Exception as e:
                        logger.warning(f"grades delete notice: {e}")
                supabase.table("answer_sheets").delete().eq("exam_id", exam_id).execute()
            except Exception as e:
                logger.warning(f"answer_sheets delete notice: {e}")
            
            try:
                supabase.table("questions").delete().eq("exam_id", exam_id).execute()
            except Exception as e:
                logger.warning(f"questions delete notice: {e}")
            
            try:
                supabase.table("exams").delete().eq("id", exam_id).execute()
            except Exception as e:
                logger.warning(f"exams delete notice: {e}")
            
        try:
            supabase.table("enrollments").delete().eq("class_id", class_id).execute()
        except Exception as e:
            logger.warning(f"enrollments delete notice: {e}")
        
        try:
            supabase.table("learning_materials").delete().eq("class_id", class_id).execute()
        except Exception as e:
            logger.warning(f"learning_materials delete notice: {e}")
        
        supabase.table("classes").delete().eq("id", class_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Delete course error: {e}")
        raise HTTPException(status_code=500, detail=f"Delete course error: {str(e)}")

@app.get("/resolve-sheet/{sheet_id}")
async def resolve_sheet(sheet_id: str, user=Depends(get_current_user)):
    """BR-05: Resolve sheet metadata by sheet_id, enforcing Instructor authorization."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database connection unconfigured")
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    try:
        # Printed codes resolve through sheet_identifier, never the internal UUID.
        if not re.fullmatch(r"CM-[A-Z0-9]{8}", sheet_id):
            raise HTTPException(status_code=422, detail="Expected an 8-character answer-sheet code (CM-XXXXXXXX)")
        res = supabase.table("answer_sheets").select("*, profiles(*), exams(*, classes(*))").eq("sheet_identifier", sheet_id).execute()

        if not res.data:
            raise HTTPException(status_code=404, detail="Sheet not found")
            
        sheet_data = res.data[0]
        profile = sheet_data.get('profiles') or {}
        sheet_data['student_name'] = profile.get('name', 'Student')
        
        # BR Authorization Gate: Ensure the current user is the instructor of the class that owns this exam
        exam = sheet_data.get('exams')
        if not exam:
            raise HTTPException(status_code=403, detail="Assessment data is corrupted or missing.")
            
        course = exam.get('classes')
        if not course or course.get('instructor_id') != user.user.id:
            raise HTTPException(status_code=403, detail="You are not authorized to evaluate this assessment.")
            
        return sheet_data
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error resolving sheet {sheet_id}: {e}")
        raise HTTPException(status_code=500, detail="Database resolve error")

@app.get("/check-sheet-scanned/{sheet_id}")
async def check_sheet_scanned(sheet_id: str, user=Depends(get_current_user)):
    sheet = await resolve_sheet(sheet_id, user)
    res = supabase.table("grades").select("id").eq("sheet_id", sheet['id']).execute()
    return {"scanned": bool(res.data)}

@app.get("/get-exam-results/{exam_id}")
async def get_exam_results(exam_id: str, user=Depends(get_current_user)):
    """Fetch all answer sheets with grades and student profiles for an exam bypassing RLS."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database unconfigured")
    _instructor_exam(exam_id, user)
    try:
        uuid.UUID(str(exam_id))
        res = supabase.table("answer_sheets").select("id, set_type, student_id, profiles(id, name, email), grades(*)").eq("exam_id", exam_id).execute()
        return res.data or []
    except Exception as e:
        logger.error(f"Get exam results error: {e}")
        return []

@app.post("/batch-save-grades")
async def batch_sync(sync_data: BatchSyncRequest, user=Depends(get_current_user)):
    """Persist reviewed local grades; one sheet per request supports any scan order."""
    if not supabase:
        raise HTTPException(status_code=500, detail="Database connection unconfigured")
    try:
        saved_results = []
        for r in sync_data.results:
            sheet = await resolve_sheet(r.sheet_id.strip(), user)
            if sheet['exam_id'] != sync_data.exam_id:
                raise HTTPException(status_code=422, detail="Sheet belongs to a different assessment")
            if r.total <= 0 or not 0 <= r.score <= r.total:
                raise HTTPException(status_code=422, detail="Invalid local grade")
            if len(r.answers) == r.total and (
                    sum(answer.get("isCorrect") is True for answer in r.answers) != r.score):
                raise HTTPException(status_code=422, detail="Local item results do not match the score")
            saved_results.append({
                "sheet_id": sheet['id'],
                "score": r.score,
                "total_questions": r.total,
                "percentage": r.score / r.total * 100,
                "answers": [{k: v for k, v in answer.items() if k in {
                    'question_number', 'question_id', 'question_text', 'question_type',
                    'topic_tag', 'answer', 'correct_answer', 'confidence', 'isCorrect', 'isAmbiguous'
                }} for answer in r.answers],
            })
        if not saved_results:
            raise HTTPException(status_code=422, detail="Scanning session is empty")
        # The existing session RPC saves the entire validated batch atomically.
        saved = supabase.rpc("save_grade_session", {"p_results": saved_results}).execute()
        if saved.data != len(saved_results):
            raise HTTPException(status_code=500, detail="Incomplete session save")
        return {"status": "success", "saved_count": len(saved_results)}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Sync error: {e}")
        raise HTTPException(status_code=500, detail="Sync Error")

def _require_user(user):
    if not user or not getattr(getattr(user, "user", None), "id", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    if not supabase:
        raise HTTPException(status_code=503, detail="Database unconfigured")
    return user.user.id


def _one(table, key, value, columns="*"):
    rows = supabase.table(table).select(columns).eq(key, value).limit(1).execute().data or []
    return rows[0] if rows else None


def _instructor_exam(exam_id, user):
    user_id = _require_user(user)
    exam = _one("exams", "id", exam_id, "id, title, class_id, results_released, classes(instructor_id)")
    if not exam:
        raise HTTPException(status_code=404, detail="Assessment not found")
    course = exam.get("classes") or {}
    if course.get("instructor_id") != user_id:
        raise HTTPException(status_code=403, detail="Instructor access required")
    return exam


def _paged(query_factory, size=500):
    rows = []
    for offset in range(0, 100000, size):
        page = query_factory().range(offset, offset + size - 1).execute().data or []
        rows.extend(page)
        if len(page) < size:
            return rows
    raise HTTPException(status_code=413, detail="Too many results for analysis")


def _questions_for_exam(exam_id):
    try:
        rows = _paged(lambda: supabase.table("questions").select(
            "id, question_text, question_type, correct_answer, topic_tag"
        ).eq("exam_id", exam_id))
        return {str(row["id"]): row for row in rows}
    except Exception as exc:
        # Legacy/offline fixtures may lack the questions relation. Item snapshots
        # still contain the data saved at scan time; do not invent missing items.
        logger.warning("Question context unavailable for %s: %s", exam_id, exc)
        return {}


def _grade_rows_for_sheet(sheet_id):
    return _paged(lambda: supabase.table("grades").select("*").eq("sheet_id", sheet_id))


def _latest_grade(grades):
    return max(grades, key=lambda grade: (grade.get("created_at") or "", str(grade.get("id") or "")))


@app.post("/analyze-class")
async def analyze_class(request: AnalysisRequest, user=Depends(get_current_user)):
    """Analyze persisted, locally graded item results for one assessment."""
    exam = _instructor_exam(request.exam_id, user)
    try:
        sheets = _paged(lambda: supabase.table("answer_sheets").select(
            "id, grades(*)"
        ).eq("exam_id", request.exam_id).order("id"))
        grades = []
        questions = _questions_for_exam(request.exam_id)
        for sheet in sheets:
            relation = sheet.get("grades") or []
            related_grades = relation if isinstance(relation, list) else [relation]
            if related_grades:
                grades.append(enrich_answers(_latest_grade(related_grades), questions))
        if not grades:
            return {"exam_id": request.exam_id, "status": "no_results", "sample_count": 0,
                    "analysis": None}
        evidence = {
            "assessment": exam.get("title"), "sample_count": len(grades),
            "average_percentage": round(sum(grade_context(g)["percentage"] for g in grades) / len(grades), 1),
            "topics": topic_counts(grades), "questions": question_counts(grades),
            # Representative item outcomes make the source of the counts auditable.
            "sample_item_results": [item for grade in grades[:20]
                                    for item in grade.get("answers", [])][:100],
        }
        metrics = {key: evidence[key] for key in ("average_percentage", "topics", "questions")}
        try:
            analysis = await generate_structured_response(
                system_prompt=SYSTEM_CLASS_ANALYSIS,
                user_prompt=get_class_analysis_prompt(json.dumps(evidence)),
                schema_class=ClassAnalysisResponse,
                model_override=HF_MODEL_REASONING,
            )
            return {"exam_id": request.exam_id, "status": "complete", "sample_count": len(grades),
                    "source": "ai", "metrics": metrics,
                    "analysis": analysis.model_dump(exclude={"reasoning"})}
        except Exception as exc:
            logger.warning("Class AI unavailable: %s", exc)
            return {"exam_id": request.exam_id, "status": "complete", "sample_count": len(grades),
                    "source": "summary", "metrics": metrics,
                    "analysis": class_summary(grades)}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Class analysis data error: %s", exc)
        raise HTTPException(status_code=500, detail="Could not load saved class results")


@app.post("/student-insight")
async def student_insight(request: StudentInsightRequest, user=Depends(get_current_user)):
    """Personal feedback for one persisted sheet, subject to release/access rules."""
    user_id = _require_user(user)
    try:
        sheet = _one("answer_sheets", "id", request.sheet_id)
        if not sheet or sheet.get("exam_id") != request.exam_id:
            raise HTTPException(status_code=404, detail="Answer sheet not found")
        exam = _one("exams", "id", request.exam_id, "id, title, results_released, classes(instructor_id)")
        if not exam:
            raise HTTPException(status_code=404, detail="Assessment not found")
        instructor_id = (exam.get("classes") or {}).get("instructor_id")
        if user_id != instructor_id and not (user_id == sheet.get("student_id") and exam.get("results_released")):
            raise HTTPException(status_code=403, detail="Result is not available to this user")
        grades = _grade_rows_for_sheet(request.sheet_id)
        if not grades:
            raise HTTPException(status_code=404, detail="Saved result not found")
        grade = _latest_grade(grades)
        if grade.get("student_insight") and not request.regenerate:
            return grade["student_insight"]
        grade = enrich_answers(grade, _questions_for_exam(request.exam_id))
        evidence = {"assessment": exam.get("title"), **grade_context(grade)}
        try:
            analysis = await generate_structured_response(
                system_prompt=SYSTEM_STUDENT_MENTOR,
                user_prompt=get_student_insight_prompt(json.dumps(evidence)),
                schema_class=StudentInsightResponse,
                model_override=HF_MODEL_REASONING,
            )
            result = {"source": "ai", "insight": analysis.model_dump(exclude={"reasoning"})}
        except Exception as exc:
            logger.warning("Student AI unavailable: %s", exc)
            result = {"source": "summary", "insight": student_summary(grade)}
        supabase.table("grades").update({"student_insight": result}).eq("id", grade["id"]).execute()
        return result
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Student insight data error: %s", exc)
        raise HTTPException(status_code=500, detail="Could not load saved student result")


@app.get("/student-overall-analysis")
@app.post("/student-overall-analysis")
async def student_overall_analysis(student_id: str | None = None, class_id: str | None = None,
                                   user=Depends(get_current_user)):
    """Private learner history, or a course instructor's student review."""
    user_id = _require_user(user)
    target_id = student_id or user_id
    instructor_view = target_id != user_id
    if instructor_view:
        if not class_id:
            raise HTTPException(status_code=422, detail="Course ID required for instructor review")
        course = _one("classes", "id", class_id)
        if not course or course.get("instructor_id") != user_id:
            raise HTTPException(status_code=403, detail="Instructor access required")
    try:
        sheets = _paged(lambda: supabase.table("answer_sheets").select("*").eq("student_id", target_id).order("id"))
        results = []
        exam_cache = {}
        question_cache = {}
        for sheet in sheets:
            exam_id = sheet.get("exam_id")
            if exam_id not in exam_cache:
                exam_cache[exam_id] = _one("exams", "id", exam_id, "id, title, class_id, results_released")
            exam = exam_cache[exam_id]
            if not exam or (class_id and exam.get("class_id") != class_id):
                continue
            if not instructor_view and not exam.get("results_released"):
                continue
            if exam_id not in question_cache:
                question_cache[exam_id] = _questions_for_exam(exam_id)
            sheet_grades = _grade_rows_for_sheet(sheet["id"])
            if sheet_grades:
                grade = _latest_grade(sheet_grades)
                context = grade_context(enrich_answers(grade, question_cache[exam_id]))
                results.append({"assessment": exam.get("title"), "created_at": grade.get("created_at"), **context})
        if not results:
            return {"status": "no_results", "sample_count": 0, "analysis": None}
        results.sort(key=lambda item: item.get("created_at") or "")
        evidence = {
            "sample_count": len(results),
            "visibility": "instructor review of saved course results" if instructor_view else "student's released results",
            "results": [{key: result.get(key) for key in (
                "assessment", "created_at", "score", "total_questions", "percentage"
            )} for result in results],
            "topics": topic_counts(results),
            "questions": question_counts(results)[:100],
            "missed_item_examples": [item for result in results
                                     for item in result.get("answers", [])
                                     if item.get("isCorrect") is False][:60],
        }
        metrics = {"topics": evidence["topics"], "questions": evidence["questions"],
                   "results": evidence["results"]}
        try:
            analysis = await generate_structured_response(
                system_prompt=SYSTEM_STUDENT_MENTOR,
                user_prompt=get_student_insight_prompt(json.dumps(evidence)),
                schema_class=StudentOverviewResponse,
                model_override=HF_MODEL_REASONING,
            )
            return {"status": "complete", "sample_count": len(results), "source": "ai",
                    "metrics": metrics,
                    "analysis": analysis.model_dump(exclude={"reasoning"})}
        except Exception as exc:
            logger.warning("Overall AI unavailable: %s", exc)
            return {"status": "complete", "sample_count": len(results), "source": "summary",
                    "metrics": metrics,
                    "analysis": student_overview_summary(results, released_only=not instructor_view)}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Overall analysis data error: %s", exc)
        raise HTTPException(status_code=500, detail="Could not load released results")

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
