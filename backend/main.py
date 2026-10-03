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
import html
import os
import json
import logging
import uuid
import time
import re
from io import BytesIO
from fastapi import FastAPI, HTTPException, Body, Depends, UploadFile, File, Form
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
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
    ClassAnalysisResponse,
    StudentInsightResponse,
    StudentOverviewResponse,
    HF_MODEL_FAST,
    HF_MODEL_REASONING,
    client as hf_client
)
from assessment_generation import (
    AssessmentValidationError,
    clean_option_label,
    generate_verified_questions,
    normalize_source_mode,
    validate_distribution,
)
from result_analysis import class_summary, enrich_answers, grade_context, question_counts, student_summary, student_overview_summary, topic_counts
from scores_export import build_scores_workbook
from ai_instructions import (
    SYSTEM_CLASS_ANALYSIS,
    SYSTEM_STUDENT_MENTOR,
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

active_generations = {}
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
    include_tf: bool = False
    mcq_count: int | None = None
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


@app.get("/email-verified", response_class=HTMLResponse)
def email_verified(
    code: str | None = None,
    error: str | None = None,
    error_code: str | None = None,
    error_description: str | None = None,
):
    confirmed = bool(code and not (error or error_code or error_description))
    title = "Email confirmed" if confirmed else "Confirmation link unavailable"
    icon = (
        '<svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="23" '
        'fill="#dcfce7"/><path d="m14 24 7 7 14-15" fill="none" stroke="#15803d" '
        'stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
        if confirmed else
        '<svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="23" '
        'fill="#fff1d6"/><path d="M24 13v13m0 8h.02" fill="none" stroke="#b45309" '
        'stroke-width="3.5" stroke-linecap="round"/></svg>'
    )
    eyebrow = "ACCOUNT VERIFIED" if confirmed else "LINK NOT VERIFIED"
    heading = "You're all set." if confirmed else "Let's get you back on track."
    message = (
        "Your email address has been confirmed. Open CheckMate and sign in to continue."
        if confirmed else
        "This link is missing, expired, or already used. Return to CheckMate and request "
        "a new confirmation email before trying again."
    )
    return HTMLResponse(
        content=(
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<meta name=\"theme-color\" content=\"#f4f6fb\"><title>"
            f"{title} · CheckMate</title><style>"
            "*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;"
            "padding:24px;background:radial-gradient(ellipse at 50% 0,#e5eaff 0,transparent 52%),"
            "#f4f6fb;color:#172033;font:16px/1.6 system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}"
            ".card{width:min(100%,460px);padding:clamp(28px,8vw,48px);border:1px solid #e6e9f0;"
            "border-radius:28px;background:#fff;box-shadow:0 24px 70px #26345b14;text-align:center}"
            ".brand{display:inline-flex;align-items:center;gap:9px;margin-bottom:40px;color:#25315b;"
            "font-size:17px;font-weight:750;letter-spacing:-.4px}.brand-mark{display:grid;place-items:center;"
            "width:30px;height:30px;border-radius:10px;background:#4658d9;color:white;font-size:14px}"
            ".icon{width:64px;height:64px;margin:0 auto 22px}.icon svg{display:block;width:100%;height:100%}"
            ".eyebrow{margin:0 0 8px;color:#64708a;font-size:11px;font-weight:750;letter-spacing:1.7px}"
            "h1{margin:0;color:#18213b;font-size:clamp(28px,7vw,36px);line-height:1.15;letter-spacing:-1.2px}"
            ".message{margin:16px auto 28px;max-width:330px;color:#667085}"
            ".button{display:flex;min-height:52px;align-items:center;justify-content:center;gap:9px;"
            "border-radius:14px;background:#4658d9;color:#fff;font-weight:700;text-decoration:none;"
            "transition:background .15s,transform .15s}.button:hover{background:#3849c3;transform:translateY(-1px)}"
            ".footnote{margin:22px 0 0;color:#8992a5;font-size:13px}"
            "@media(prefers-reduced-motion:reduce){.button{transition:none}}</style>"
            "<meta name=\"referrer\" content=\"no-referrer\"></head><body><main class=\"card\">"
            "<div class=\"brand\"><span class=\"brand-mark\" aria-hidden=\"true\">C</span>CheckMate</div>"
            f"<div class=\"icon\">{icon}</div><p class=\"eyebrow\">{eyebrow}</p>"
            f"<h1>{heading}</h1><p class=\"message\">{message}</p>"
            "<a class=\"button\" href=\"checkmate://\">Open CheckMate <span aria-hidden=\"true\">&#8594;</span></a>"
            "<p class=\"footnote\">"
            + ("You can close this page once the app opens." if confirmed
               else "For your security, confirmation links can only be used once.")
            + "</p></main></body></html>"
        ),
        status_code=200 if confirmed else 400,
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        },
    )


def _course_invite_page(message: str, status_code: int) -> HTMLResponse:
    safe_message = html.escape(message)
    return HTMLResponse(
        content=(
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<meta name=\"theme-color\" content=\"#f4f6fb\"><title>Invitation unavailable · CheckMate</title>"
            "<style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;"
            "padding:24px;background:#f4f6fb;color:#172033;font:16px/1.6 system-ui,sans-serif}"
            ".card{width:min(100%,460px);padding:clamp(28px,8vw,48px);border:1px solid #e6e9f0;"
            "border-radius:28px;background:#fff;box-shadow:0 24px 70px #26345b14;text-align:center}"
            ".mark{display:grid;place-items:center;width:34px;height:34px;margin:0 auto 30px;"
            "border-radius:11px;background:#4658d9;color:white;font-weight:750}"
            "h1{margin:0;color:#18213b;font-size:30px;letter-spacing:-.8px}"
            "p{margin:16px 0 0;color:#667085}</style>"
            "<meta name=\"referrer\" content=\"no-referrer\"></head><body><main class=\"card\">"
            "<div class=\"mark\" aria-hidden=\"true\">C</div><h1>Invitation unavailable</h1>"
            f"<p>{safe_message}</p></main></body></html>"
        ),
        status_code=status_code,
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        },
    )


def _private_course_invite_page(invite_token: str) -> HTMLResponse:
    app_link = html.escape(
        f"checkmate://join?inviteToken={invite_token}", quote=True,
    )
    return HTMLResponse(
        content=(
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<meta name=\"theme-color\" content=\"#f4f6fb\"><title>Course invitation · CheckMate</title>"
            "<style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;"
            "padding:24px;background:radial-gradient(ellipse at 50% 0,#e5eaff 0,transparent 52%),"
            "#f4f6fb;color:#172033;font:16px/1.6 system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}"
            ".card{width:min(100%,460px);padding:clamp(28px,8vw,48px);border:1px solid #e6e9f0;"
            "border-radius:28px;background:#fff;box-shadow:0 24px 70px #26345b14;text-align:center}"
            ".brand{display:inline-flex;align-items:center;gap:9px;margin-bottom:40px;color:#25315b;"
            "font-size:17px;font-weight:750}.mark{display:grid;place-items:center;width:30px;height:30px;"
            "border-radius:10px;background:#4658d9;color:white}.icon{width:64px;height:64px;margin:0 auto 22px;"
            "display:grid;place-items:center;border-radius:50%;background:#e7eaff;color:#4658d9;font-size:30px}"
            ".eyebrow{margin:0 0 8px;color:#64708a;font-size:11px;font-weight:750;letter-spacing:1.7px}"
            "h1{margin:0;color:#18213b;font-size:clamp(28px,7vw,36px);line-height:1.15;letter-spacing:-1px}"
            ".message{margin:16px auto 28px;max-width:330px;color:#667085}"
            ".button{display:flex;min-height:52px;align-items:center;justify-content:center;gap:9px;"
            "border-radius:14px;background:#4658d9;color:#fff;font-weight:700;text-decoration:none}"
            ".footnote{margin:22px 0 0;color:#8992a5;font-size:13px}</style>"
            "<meta name=\"referrer\" content=\"no-referrer\"></head><body><main class=\"card\">"
            "<div class=\"brand\"><span class=\"mark\" aria-hidden=\"true\">C</span>CheckMate</div>"
            "<div class=\"icon\" aria-hidden=\"true\">&#8594;</div><p class=\"eyebrow\">COURSE INVITATION</p>"
            "<h1>You're invited.</h1><p class=\"message\">Open this invitation in CheckMate to join your course. "
            "Sign in or create an account if prompted.</p>"
            f"<a class=\"button\" href=\"{app_link}\">Open CheckMate <span aria-hidden=\"true\">&#8594;</span></a>"
            "<p class=\"footnote\">This private invitation link expires in 7 days.</p>"
            "</main></body></html>"
        ),
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; "
            "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        },
    )


@app.get("/join", response_class=HTMLResponse)
def course_invitation(
    inviteToken: str | None = None,
    code: str = "",
    joinCode: str | None = None,
):
    if not inviteToken:
        return _course_invite_page(
            message="This older invitation link is no longer valid. Ask the instructor to share a new invitation.",
            status_code=410 if code or joinCode else 400,
        )
    if not re.fullmatch(r"[A-Fa-f0-9]{64}", inviteToken):
        return _course_invite_page(
            message="This invitation link is invalid. Ask the instructor to share a new invitation.",
            status_code=400,
        )
    if not supabase:
        return _course_invite_page(
            message="Course invitations are temporarily unavailable. Please try again later.",
            status_code=503,
        )
    result = supabase.rpc(
        "is_course_invitation_valid", {"p_token": inviteToken},
    ).execute()
    if not result.data:
        return _course_invite_page(
            message="This invitation has expired or is no longer active. Ask the instructor to share a new invitation.",
            status_code=410,
        )
    return _private_course_invite_page(inviteToken)


@app.get("/.well-known/assetlinks.json")
def android_app_links():
    return JSONResponse(
        content=[{
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.checkmate.checkmate",
                "sha256_cert_fingerprints": [
                    "C1:9A:8B:E3:C3:83:48:3C:DB:5D:D7:41:D7:8F:22:67:"
                    "3B:D1:32:43:A2:B5:46:D2:89:1B:CE:77:3C:97:93:67",
                    "6E:D3:E3:E6:FE:80:78:D5:17:5F:BE:06:95:B9:1A:46:"
                    "A7:55:DC:21:CE:B9:AD:F1:2A:0F:A7:C9:77:6E:A9:72",
                ],
            },
        }],
        headers={"Cache-Control": "public, max-age=3600"},
    )


def _assessment_event(event_type: str, **payload) -> str:
    return f"data: {json.dumps({'type': event_type, **payload}, ensure_ascii=False)}\n\n"


def _verified_question_text(question: dict, number: int) -> str:
    lines = [f"\n{number}. {question['questionText']}"]
    for index, option in enumerate(question["options"]):
        lines.append(f"{chr(65 + index)}) {option}")
    return "\n".join(lines) + "\n"


def _ordered_question_id(index: int, base_millis: int) -> str:
    """UUIDv7 with an increasing millisecond prefix to retain printed order."""
    value = bytearray(uuid.uuid4().bytes)
    value[:6] = (base_millis + index).to_bytes(6, "big")
    value[6] = (value[6] & 0x0F) | 0x70
    value[8] = (value[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(value)))


def _stored_question_text(question: dict) -> str:
    text = str(question.get("questionText") or question.get("question_text") or question.get("text") or "")
    options = question.get("options") or []
    if (question.get("questionType") or question.get("question_type")) == "MCQ" and len(options) == 4:
        return text + "\n" + "\n".join(
            f"{chr(65 + index)}. {clean_option_label(option, index)}"
            for index, option in enumerate(options))
    return text


def _restored_question(row: dict) -> dict:
    question = dict(row)
    lines = str(question.get("question_text") or "").splitlines()
    if question.get("question_type") == "MCQ" and len(lines) >= 5:
        matches = [re.fullmatch(rf"{chr(65 + index)}[.)]\s*(.+)", line.strip())
                   for index, line in enumerate(lines[-4:])]
        if all(matches):
            question["question_text"] = "\n".join(lines[:-4]).strip()
            question["options"] = [clean_option_label(match.group(1), index)
                                   for index, match in enumerate(matches)]
    elif question.get("question_type") == "TF":
        question["options"] = ["True", "False"]
    return question


@app.post("/generate-exam")
async def generate_exam(request: ExamRequest):
    """Return a fully checked preview; the instructor explicitly saves the draft."""
    try:
        mcq_count = request.mcq_count if request.mcq_count is not None else request.question_count - request.tf_count
        validate_distribution(request.question_count, mcq_count,
                              request.tf_count, request.include_mcq, request.include_tf)
        material = request.material or request.topic
        questions = await generate_verified_questions(material, mcq_count,
                                                      request.tf_count)
        return {"exam_id": "temp-dev-id", "questions": questions}
    except AssessmentValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Assessment generation failed")
        raise HTTPException(status_code=502, detail=f"AI processing failed: {exc}") from exc


@app.post("/generate-exam-stream")
async def generate_exam_stream(
    topic: str = Form("Uploaded material"),
    class_id: str = Form(...),
    question_count: int = Form(5),
    assessment_type: str = Form("Quiz"),
    include_mcq: bool = Form(True),
    include_tf: bool = Form(False),
    mcq_count: int = Form(5),
    tf_count: int = Form(0),
    source_mode: str = Form("topic"),
    has_multiple_sets: bool = Form(False),
    file: UploadFile | None = File(None),
):
    """Stream progress while generating and auditing exact, structured questions."""
    try:
        validate_distribution(question_count, mcq_count, tf_count,
                              include_mcq, include_tf)
    except AssessmentValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    source_mode = normalize_source_mode(source_mode)
    task_key = (class_id, topic, assessment_type, source_mode, mcq_count, tf_count)

    filename = file.filename if file else None
    logger.info(
        "Starting assessment stream (source_mode=%s, uploaded_file=%s)",
        source_mode, bool(filename),
    )
    content_bytes = await file.read() if file else None
    if content_bytes and len(content_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Uploaded files must be 10 MB or smaller.")

    queue = asyncio.Queue()
    # A retry replaces the earlier stream. Closing a Flutter subscription does
    # not always stop its server worker immediately, so the old task must not
    # block the new assessment request.
    previous_task = active_generations.get(task_key)
    if previous_task is not None:
        previous_task.cancel()

    async def report(message):
        # Keep operational details out of the student-facing live preview.
        if message.startswith("Generating"):
            phase = "Writing the next questions"
        elif message.startswith("Formatting"):
            phase = "Formatting your questions"
        elif message.startswith("Checking"):
            phase = "Finalizing assessment"
        elif message.startswith("Accepted"):
            phase = "Preparing more questions"
        else:
            phase = "Refining the assessment"
        await queue.put(_assessment_event("progress", content=phase))

    async def show_question(question, number):
        preview = {key: value for key, value in question.items()
                   if key not in ("correctAnswer", "reasoning", "verification")}
        await queue.put(_assessment_event("question", number=number, question=preview))
        # Older app builds only understand token events. They still receive each
        # verified question in real time, never an unchecked model proposal.
        await queue.put(_assessment_event("token", content=_verified_question_text(question, number)))

    async def show_draft(text, kind):
        await queue.put(_assessment_event("draft", questionType=kind, text=text))

    async def generation_worker():
        try:
            material = topic
            if filename:
                await report(f"Reading {filename}...")
                class FileName:
                    def __init__(self, value):
                        self.filename = value
                extracted = extract_text_from_file(FileName(filename), content_bytes)
                if not extracted.strip():
                    raise AssessmentValidationError("No readable text was found in the uploaded file.")
                material = f"Source file: {filename}\n{extracted}\nAdditional topic: {topic}"
            preparation = ("Preparing supplied questions...\n" if source_mode == "existing_questions"
                           else "Preparing verified questions...\n")
            await queue.put(_assessment_event("token", content=preparation))
            await report("Preparing structured assessment...")
            questions = await generate_verified_questions(
                material, mcq_count, tf_count, source_mode, report, show_question,
                show_draft)
            await queue.put(_assessment_event("complete", exam_id="temp-dev-id", questions=questions))
        except Exception as exc:
            logger.exception("Assessment generation failed")
            await queue.put(_assessment_event("error", content=str(exc)))
        finally:
            if active_generations.get(task_key) is asyncio.current_task():
                active_generations.pop(task_key, None)
            await queue.put(None)

    task = asyncio.create_task(generation_worker())
    active_generations[task_key] = task
    background_tasks_refs.add(task)
    def clear_generation_task(completed):
        background_tasks_refs.discard(completed)
        if active_generations.get(task_key) is completed:
            active_generations.pop(task_key, None)
    task.add_done_callback(clear_generation_task)

    async def event_generator():
        try:
            while True:
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=15)
                except asyncio.TimeoutError:
                    yield ": keep-alive\n\n"
                    continue
                if item is None:
                    break
                yield item
        finally:
            if not task.done():
                pass # Do not cancel task on disconnect so it continues background generation

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
            base_millis = time.time_ns() // 1_000_000
            inserts = [{
                "id": _ordered_question_id(index, base_millis),
                "exam_id": exam_id,
                "question_text": _stored_question_text(q),
                "correct_answer": str(q.get('correctAnswer', 'A')),
                "question_type": str(q.get('questionType', 'MCQ')),
                "topic_tag": str(q.get('topicTag', request.title))
            } for index, q in enumerate(request.questions)]
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
        ordered = sorted(res.data or [], key=lambda q: (q.get("question_type") != "MCQ", q["id"]))
        return [_restored_question(question) for question in ordered]
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
async def get_exams(class_id: str, user=Depends(get_current_user)):
    """Instructors see drafts; enrolled students see approved assessments."""
    user_id = _require_user(user)
    course = _one("classes", "id", class_id, "id, instructor_id")
    if not course:
        raise HTTPException(status_code=404, detail="Class not found")
    is_instructor = course.get("instructor_id") == user_id
    if not is_instructor:
        enrollment = supabase.table("enrollments").select("id").eq(
            "class_id", class_id).eq("user_id", user_id).limit(1).execute().data
        if not enrollment:
            raise HTTPException(status_code=403, detail="Class access required")
    try:
        columns = ("*, questions(id, question_type), answer_sheets(id, grades(percentage))"
                   if is_instructor else "*, questions(id, question_type)")
        query = supabase.table("exams").select(columns).eq("class_id", class_id)
        if not is_instructor:
            query = query.eq("is_approved", True)
        res = query.order("created_at", desc=True).execute()
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


@app.get("/my-exam-result/{exam_id}")
async def my_exam_result(exam_id: str, user=Depends(get_current_user)):
    """Return only the caller's saved, released grade and item evaluations."""
    user_id = _require_user(user)
    exam = _one("exams", "id", exam_id, "id, results_released")
    if not exam or exam.get("results_released") is not True:
        raise HTTPException(status_code=404, detail="Released result not found")
    sheets = _paged(lambda: supabase.table("answer_sheets").select("id")
                    .eq("exam_id", exam_id).eq("student_id", user_id))
    grades = [grade for sheet in sheets
              for grade in _grade_rows_for_sheet(sheet["id"])]
    if not grades:
        raise HTTPException(status_code=404, detail="Saved result not found")
    grade = enrich_answers(_latest_grade(grades), _questions_for_exam(exam_id))
    return {"grade": grade, "insight": grade.get("student_insight")}


@app.get("/export-scores/{exam_id}")
async def export_scores(exam_id: str, user=Depends(get_current_user)):
    """Download saved assessment scores as an instructor-only XLSX file."""
    exam = _instructor_exam(exam_id, user)
    try:
        course = _one("classes", "id", exam["class_id"], "name") or {}
        sheets = _paged(lambda: supabase.table("answer_sheets").select(
            "id, sheet_identifier, student_id, set_type, profiles(name, email), "
            "grades(id, score, total_questions, percentage, created_at)"
        ).eq("exam_id", exam_id).order("id"))
        submissions = []
        for sheet in sheets:
            relation = sheet.get("grades") or []
            grades = relation if isinstance(relation, list) else [relation]
            if not grades:
                continue
            grade = _latest_grade(grades)
            profile = sheet.get("profiles") or {}
            submissions.append({
                "student_name": profile.get("name") or profile.get("email") or "Student",
                "student_email": profile.get("email") or "",
                "set_type": sheet.get("set_type") or "A",
                "score": grade.get("score"),
                "total_questions": grade.get("total_questions"),
                "percentage": grade.get("percentage"),
                "created_at": grade.get("created_at"),
                "sheet_code": sheet.get("sheet_identifier") or "",
            })
        workbook = build_scores_workbook(
            exam.get("title") or "Assessment", course.get("name") or "Class",
            submissions, results_released=exam.get("results_released") is True,
        )
        filename = f"CheckMate_Scores_{exam_id[:8]}.xlsx"
        return StreamingResponse(workbook, media_type=(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Score export failed for %s: %s", exam_id, exc)
        raise HTTPException(status_code=500, detail="Could not export scores")


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
