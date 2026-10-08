import os
import json
import logging
import re
import time
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field, ValidationError, ConfigDict
from openai import AsyncOpenAI
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from dotenv import load_dotenv

# Ensure environment variables are loaded before configuring the client
load_dotenv()

logger = logging.getLogger("CheckMateAI")

# Configure Client for OpenRouter
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
HF_MODEL_REASONING = os.getenv("OPENROUTER_MODEL_REASONING", "meta-llama/llama-3.3-70b-instruct").strip()
HF_MODEL_FAST = os.getenv("OPENROUTER_MODEL_FAST", "meta-llama/llama-3.1-8b-instruct").strip()
OPENROUTER_PROVIDER_SORT = os.getenv("OPENROUTER_PROVIDER_SORT", "throughput").strip()

# Fallback model string, though specific models are now passed in the function call
DEFAULT_HF_MODEL = HF_MODEL_REASONING

client = None
if OPENROUTER_API_KEY:
    client = AsyncOpenAI(
        base_url="https://openrouter.ai/api/v1",
        api_key=OPENROUTER_API_KEY,
        timeout=120.0,
        max_retries=0,
    )
    logger.info("OpenRouter Client initialized successfully.")
else:
    logger.error("OPENROUTER_API_KEY is missing!")

# --- PYDANTIC SCHEMAS ---

class Question(BaseModel):
    reasoning: str = Field(..., description="Short, checkable explanation supporting the answer key.")
    part: int = Field(..., description="1 for MCQ, 2 for True/False")
    questionType: str = Field(..., description="'MCQ' or 'TF'")
    questionText: str = Field(..., description="The actual question text")
    options: List[str] = Field(..., description="List of options. For TF, must be ['True', 'False']")
    correctAnswer: str = Field(..., description="The correct answer letter (e.g., 'A', 'B')")
    topicTag: str = Field(..., description="A short tag representing the topic")

class AssessmentResponse(BaseModel):
    questions: List[Question]

class AnswerAuditItem(BaseModel):
    number: int
    answer: str
    verified: bool
    justification: str

class AnswerAuditResponse(BaseModel):
    items: List[AnswerAuditItem]

class ClassAnalysisResponse(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    insights: str = Field(min_length=1, description="Pedagogical insights grounded in the supplied results.")
    recommendations: str = Field(min_length=1, description="Actionable teaching recommendations.")

class StudentInsightResponse(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    performanceSummary: str = Field(min_length=1)
    strengths: List[str]
    learningGaps: List[str]
    actionableSteps: List[str] = Field(min_length=1)

class StudentOverviewResponse(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    performanceSummary: str = Field(min_length=1)
    strengths: List[str]
    learningGaps: List[str]
    actionableSteps: List[str] = Field(min_length=1)

# --- AI CORE FUNCTIONS ---

def parse_json_safely(content: str) -> dict:
    """Parses JSON content, stripping markdown code blocks and malformed wrappers."""
    cleaned = str(content).strip()
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    elif cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    cleaned = cleaned.strip()

    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start != -1 and end != -1 and end > start:
        cleaned = cleaned[start:end + 1]

    if not cleaned:
        raise ValueError("AI response was empty")

    return json.loads(cleaned)

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type((ValueError, ValidationError, Exception)),
    reraise=True
)
async def generate_structured_response(system_prompt: str, user_prompt: str, schema_class: type[BaseModel], model_override: str = None, max_tokens: int = 8192, temperature: float = 0.3) -> BaseModel:
    if not client:
        raise Exception("OPENROUTER_API_KEY is not configured. AI engine is offline.")

    # Use the specific requested model, or fallback to the default
    model_to_use = model_override if model_override else DEFAULT_HF_MODEL

    # Use the validator's schema as the single contract for every AI response.
    schema = json.dumps(schema_class.model_json_schema())
    injected_system_prompt = (
        f"{system_prompt}\n\nReturn a JSON object containing the completed feedback, "
        f"not the schema itself. It must conform to this JSON Schema:\n{schema}"
    )

    try:
        response = await client.chat.completions.create(
            model=model_to_use,
            messages=[
                {"role": "system", "content": injected_system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=temperature,
            max_tokens=max_tokens,
            response_format={"type": "json_object"}
        )

        content = response.choices[0].message.content

        raw_dict = parse_json_safely(content)

        # Validate through Pydantic
        validated_data = schema_class.model_validate(raw_dict)
        return validated_data

    except Exception as e:
        logger.error(f"Failed generation attempt: {type(e).__name__} - {str(e)}")
        raise


class _JsonArrayObjectParser:
    """Extract completed objects from a streamed JSON array without waiting for its end."""

    def __init__(self, array_key: str):
        self.array_key = array_key
        self.buffer = ""
        self.position = 0
        self.object_start = None
        self.depth = 0
        self.in_string = False
        self.escaped = False
        self.started = False
        self.closed = False
        self.emitted = 0

    def feed(self, chunk: str) -> list[dict]:
        self.buffer += chunk
        if not self.started:
            match = re.search(
                rf'"{re.escape(self.array_key)}"\s*:\s*\[',
                self.buffer,
            )
            if match is None:
                if len(self.buffer) > 65536:
                    raise ValueError(f"No {self.array_key} array in the streamed response")
                return []
            self.started = True
            self.position = match.end()
        items = []
        while self.position < len(self.buffer) and not self.closed:
            char = self.buffer[self.position]
            if self.object_start is None:
                if char == "{":
                    self.object_start = self.position
                    self.depth = 1
                    self.in_string = False
                    self.escaped = False
                elif char == "]":
                    self.closed = True
                elif char not in " \t\r\n,":
                    raise ValueError(f"Malformed {self.array_key} array")
            elif self.in_string:
                if self.escaped:
                    self.escaped = False
                elif char == "\\":
                    self.escaped = True
                elif char == '"':
                    self.in_string = False
            elif char == '"':
                self.in_string = True
            elif char == "{":
                self.depth += 1
            elif char == "}":
                self.depth -= 1
                if self.depth == 0:
                    items.append(json.loads(self.buffer[self.object_start:self.position + 1]))
                    self.emitted += 1
                    self.object_start = None
            self.position += 1
        return items

    def current_question_text(self) -> str | None:
        """Decode the question stem written so far, without exposing its draft key."""
        if self.array_key != "questions" or self.object_start is None:
            return None
        partial = self.buffer[self.object_start:]
        match = re.search(r'"questionText"\s*:\s*"', partial)
        if match is None:
            return None
        result = []
        index = match.end()
        escapes = {'"': '"', "\\": "\\", "/": "/", "n": " ", "r": " ", "t": " "}
        while index < len(partial):
            char = partial[index]
            if char == '"':
                break
            if char == "\\":
                if index + 1 >= len(partial):
                    break
                next_char = partial[index + 1]
                if next_char == "u":
                    digits = partial[index + 2:index + 6]
                    if len(digits) < 4 or not re.fullmatch(r"[0-9a-fA-F]{4}", digits):
                        break
                    result.append(chr(int(digits, 16)))
                    index += 6
                    continue
                result.append(escapes.get(next_char, next_char))
                index += 2
                continue
            result.append(char)
            index += 1
        return "".join(result)

    def finish(self):
        if not self.closed or self.object_start is not None:
            raise ValueError(f"Incomplete {self.array_key} array in streamed response")


async def stream_structured_array(system_prompt: str, user_prompt: str,
                                  schema_class: type[BaseModel], array_key: str,
                                  item_class: type[BaseModel], model_override: str = None,
                                  max_tokens: int = 8192, temperature: float = 0.3,
                                  on_partial=None, max_items: int | None = None):
    """Yield validated JSON array items as soon as each item's closing brace arrives."""
    if not client:
        raise RuntimeError("OPENROUTER_API_KEY is not configured. AI engine is offline.")
    schema = json.dumps(schema_class.model_json_schema())
    injected_system_prompt = (
        f"{system_prompt}\n\nReturn a JSON object containing the completed feedback, "
        f"not the schema itself. It must conform to this JSON Schema:\n{schema}"
    )
    stream = await client.chat.completions.create(
        model=model_override or DEFAULT_HF_MODEL,
        messages=[
            {"role": "system", "content": injected_system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=temperature,
        max_tokens=max_tokens,
        response_format={"type": "json_object"},
        stream=True,
        extra_body={"provider": {"sort": OPENROUTER_PROVIDER_SORT}},
    )
    parser = _JsonArrayObjectParser(array_key)
    last_partial = ""
    last_partial_at = 0.0
    async for chunk in stream:
        delta = chunk.choices[0].delta.content if chunk.choices else None
        emitted_before = parser.emitted
        completed = parser.feed(delta or "")
        for index, raw in enumerate(completed, emitted_before + 1):
            if (on_partial and array_key == "questions" and raw.get("questionText")
                    and (max_items is None or index <= max_items)):
                await on_partial(str(raw["questionText"]), index)
                last_partial = ""
            try:
                yield item_class.model_validate(raw)
            except ValidationError:
                logger.warning("Skipping malformed %s item in model stream", array_key)
        partial = (parser.current_question_text()
                   if on_partial and (max_items is None or parser.emitted < max_items)
                   else None)
        now = time.monotonic()
        if partial and partial != last_partial and (
            now - last_partial_at >= 0.12 or len(partial) - len(last_partial) >= 16
        ):
            await on_partial(partial, parser.emitted + 1)
            last_partial = partial
            last_partial_at = now
    parser.finish()
