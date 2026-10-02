"""Assessment contracts and independent answer-key checks.

The model may propose questions, but its formatting and proposed key are never
accepted merely because JSON parsing succeeded. This module does not grade OMR.
"""

import ast
import hashlib
import json
import random
import re
from collections import Counter
from fractions import Fraction


class AssessmentValidationError(ValueError):
    pass


def normalize_source_mode(source_mode):
    value = str(source_mode or "").strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "existing_question": "existing_questions",
        "existing_questions": "existing_questions",
        "existing_question_mode": "existing_questions",
        "existing_questions_mode": "existing_questions",
        "existingquestions": "existing_questions",
        "existing": "existing_questions",
        "supplied_questions": "existing_questions",
        "supplied": "existing_questions",
    }
    return aliases.get(value, value)


def _looks_like_existing_question_bank(material, mcq_count, tf_count):
    text = str(material or "")
    if len(text) < 40:
        return False
    question_markers = re.findall(r"(?m)^\s*\d+\s*[.)]\s+\S", text)
    if len(question_markers) < min(2, mcq_count + tf_count):
        return False
    has_answer_key_header = bool(re.search(
        r"(?im)^\s*(?:answer\s*key|answers)\s*:?\s*$", text,
    ))
    has_inline_answer = bool(re.search(
        r"(?i)\b(?:correct\s+answer|answer|ans)\s*(?::|=|\bis\b|-)\s*"
        r"(?:option\s*)?(?:true|false|[A-D])\b", text,
    ))
    if not (has_answer_key_header or has_inline_answer):
        return False
    if mcq_count:
        return all(re.search(rf"(?im)^\s*{letter}[\).]\s+\S", text)
                   for letter in "ABCD")
    return bool(re.search(r"(?i)\b(?:true|false)\b", text))


def validate_distribution(total, mcq_count, tf_count, include_mcq, include_tf):
    if not 1 <= total <= 50:
        raise AssessmentValidationError("Choose between 1 and 50 questions.")
    if mcq_count < 0 or tf_count < 0 or mcq_count + tf_count != total:
        raise AssessmentValidationError("MCQ and True/False counts must add up to the total.")
    if include_mcq != (mcq_count > 0) or include_tf != (tf_count > 0):
        raise AssessmentValidationError("Question-type selections do not match the selected counts.")


def _clean_text(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _source_answer_key(material, question_text, occurrence):
    """Read an explicit inline or numbered key when the source exposes one."""
    compact = []
    offsets = []
    for index, character in enumerate(material.casefold()):
        if character.isalnum():
            compact.append(character)
            offsets.append(index)
    needle = "".join(character for character in question_text.casefold()
                     if character.isalnum())
    matches = list(re.finditer(re.escape(needle), "".join(compact))) if needle else []
    if occurrence >= len(matches):
        return None
    match = matches[occurrence]
    start, end = offsets[match.start()], offsets[match.end() - 1] + 1
    line_start = material.rfind("\n", 0, start) + 1
    prefix = material[line_start:start]
    number_match = re.fullmatch(r"\s*(\d+)\s*[.)]\s*", prefix)
    if number_match:
        next_question = re.search(r"(?m)^\s*\d+\s*[.)]\s+\S", material[end:])
        block_end = end + next_question.start() if next_question else len(material)
        block = material[end:block_end]
        inline = re.search(
            r"\b(?:correct\s+answer|answer|ans)\s*(?::|=|\bis\b|-)\s*"
            r"(?:option\s*)?(true|false|[A-D])\b", block, re.I,
        )
        if inline:
            value = inline.group(1).upper()
            return {"TRUE": "A", "FALSE": "B"}.get(value, value)
        key_section = re.search(r"(?im)^\s*(?:answer\s*key|answers)\s*:?\s*$", material)
        if key_section:
            key_line = re.search(
                rf"(?im)^\s*{number_match.group(1)}\s*[.):=-]\s*"
                r"(true|false|[A-D])\s*$", material[key_section.end():],
            )
            if key_line:
                value = key_line.group(1).upper()
                return {"TRUE": "A", "FALSE": "B"}.get(value, value)
    else:
        nearby = material[end:end + 600]
        inline = re.search(
            r"\b(?:correct\s+answer|answer|ans)\s*(?::|=|\bis\b|-)\s*"
            r"(?:option\s*)?(true|false|[A-D])\b", nearby, re.I,
        )
        if inline:
            value = inline.group(1).upper()
            return {"TRUE": "A", "FALSE": "B"}.get(value, value)
    return None


def clean_option_label(value, index):
    """Keep option content separate from the A-D label supplied by the UI."""
    text = _clean_text(value)
    label = chr(65 + index)
    return re.sub(rf"^(?:{label}[.):]\s*)+", "", text, flags=re.I).strip()


def _option_number(value):
    text = _clean_text(value).lower().rstrip(".")
    text = re.sub(r"^(?:[a-d][).:]\s*)+", "", text)
    text = re.sub(r"^(?:the\s+)?(?:order|degree|option)\s*(?:is|of|=)?\s*", "", text)
    text = re.sub(r"\s*(?:-|\s)*(?:order|degree)$", "", text)
    text = re.sub(r"(?<=\d)(?:st|nd|rd|th)$", "", text)
    words = {"zero": 0, "one": 1, "first": 1, "two": 2, "second": 2,
             "three": 3, "third": 3, "four": 4, "fourth": 4,
             "five": 5, "fifth": 5, "six": 6, "sixth": 6}
    if text in words:
        return Fraction(words[text])
    try:
        return Fraction(text.replace(" ", ""))
    except (ValueError, ZeroDivisionError):
        return None


def _safe_arithmetic(expression):
    """Evaluate only bounded numeric arithmetic, never names or calls."""
    expression = expression.replace("^", "**").replace("×", "*").replace("÷", "/")
    node = ast.parse(expression, mode="eval")

    def visit(part):
        if isinstance(part, ast.Expression):
            return visit(part.body)
        if isinstance(part, ast.Constant) and type(part.value) in (int, float):
            if abs(part.value) > 1000000:
                raise ValueError("Number is outside the arithmetic verifier's range")
            return Fraction(str(part.value))
        if isinstance(part, ast.UnaryOp) and isinstance(part.op, (ast.UAdd, ast.USub)):
            value = visit(part.operand)
            return value if isinstance(part.op, ast.UAdd) else -value
        if isinstance(part, ast.BinOp) and isinstance(part.op, (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.Pow)):
            left, right = visit(part.left), visit(part.right)
            if isinstance(part.op, ast.Add):
                value = left + right
            elif isinstance(part.op, ast.Sub):
                value = left - right
            elif isinstance(part.op, ast.Mult):
                value = left * right
            elif isinstance(part.op, ast.Div):
                value = left / right
            else:
                if right.denominator != 1 or abs(right.numerator) > 8:
                    raise ValueError("Exponent is outside the verifier's range")
                value = left ** right.numerator
            if abs(value) > 1000000000:
                raise ValueError("Result is outside the verifier's range")
            return value
        raise ValueError("Not a simple arithmetic expression")

    return visit(node)


def _derivative_order(question_text):
    text = question_text.lower().replace("′", "'").replace("″", "''").replace("‴", "'''")
    text = text.replace("²", "^2").replace("³", "^3").replace("⁴", "^4")
    orders = [int(number) for number in re.findall(
        r"d\s*\^\s*(\d+)\s*y\s*/\s*d\s*x\s*\^\s*\d+", text)]
    if re.search(r"\bd\s*y\s*/\s*d\s*x\b", text):
        orders.append(1)
    orders.extend(len(primes) for primes in re.findall(r"\by\s*('{1,6})", text))
    return max(orders) if orders else None


def _derivative_degree(question_text):
    """Degree of a simple polynomial equation in its highest derivative."""
    text = question_text.lower().replace("′", "'").replace("″", "''").replace("‴", "'''")
    if any(marker in text for marker in ("sqrt", "√", "log(", "sin(", "cos(")):
        return None
    terms = []
    for match in re.finditer(r"\bd\s*\^\s*(\d+)\s*y\s*/\s*d\s*x\s*\^\s*\d+\s*\)?\s*(?:\^\s*(\d+))?", text):
        terms.append((int(match.group(1)), int(match.group(2) or 1)))
    for match in re.finditer(r"\bd\s*y\s*/\s*d\s*x\s*\)?\s*(?:\^\s*(\d+))?", text):
        terms.append((1, int(match.group(1) or 1)))
    for match in re.finditer(r"\by\s*('{1,6})\s*\)?\s*(?:\^\s*(\d+))?", text):
        terms.append((len(match.group(1)), int(match.group(2) or 1)))
    if not terms:
        return None
    highest = max(order for order, _ in terms)
    return max(degree for order, degree in terms if order == highest)


def _deterministic_value(question):
    text = _clean_text(question["questionText"])
    lower = text.lower()
    if question["questionType"] == "TF" and "differential equation" in lower:
        statement = re.search(
            r"\bhas\s+(?:an?\s+)?(order|degree)\s+(?:of\s+)?(\d+)\s*\.?\s*$",
            lower,
        )
        if statement:
            measure = (_derivative_order(text) if statement.group(1) == "order"
                       else _derivative_degree(text))
            if measure is not None:
                return "True" if measure == int(statement.group(2)) else "False"
        if re.search(r"order.*always\s+equal\s+to.*degree|degree.*always\s+equal\s+to.*order", lower):
            return "False"
        if re.search(r"degree.*always\s+(?:greater|less).*order|order.*always\s+(?:greater|less).*degree", lower):
            return "False"
        if re.search(r"\b(?:degree|order)\s+(\d+)\s+can\s+have\s+(?:an?\s+)?(?:degree|order)\s+(?:of\s+)?(\d+)", lower):
            numbers = [int(number) for number in re.findall(r"\b\d+\b", lower)]
            if len(numbers) == 2 and all(number > 0 for number in numbers):
                return "True"
        if re.search(r"order.*always\s+an?\s+integer", lower):
            return "True"

    if question["questionType"] != "MCQ":
        return None
    if re.search(r"\b(?:what|determine|find).*\border\b.*\b(?:differential equation|derivative in the equation)\b", lower):
        return _derivative_order(text)
    if re.search(r"\b(?:what|determine|find).*\bdegree\b.*\b(?:differential equation|derivative in the equation)\b", lower):
        return _derivative_degree(text)
    arithmetic = re.fullmatch(r"(?:what is|calculate|evaluate)\s+([\d\s+\-*/().^×÷]+)\s*\??", lower)
    if arithmetic:
        try:
            return _safe_arithmetic(arithmetic.group(1).strip().rstrip("?"))
        except (ValueError, SyntaxError, ZeroDivisionError, OverflowError):
            return None
    word_problem = re.fullmatch(
        r"(?:what is|calculate|find)\s+(?:the\s+)?"
        r"(sum|difference|product|quotient)\s+of\s+(-?[\d,]+)\s+and\s+(-?[\d,]+)\s*\??",
        lower,
    )
    if word_problem:
        operation, first, second = word_problem.groups()
        if not all(re.fullmatch(r"-?(?:\d+|\d{1,3}(?:,\d{3})+)", value)
                   for value in (first, second)):
            return None
        left, right = Fraction(int(first.replace(",", ""))), Fraction(int(second.replace(",", "")))
        if max(abs(left), abs(right)) > 1000000 or (operation == "quotient" and not right):
            return None
        value = {"sum": lambda: left + right,
                 "difference": lambda: left - right,
                 "product": lambda: left * right,
                 "quotient": lambda: left / right}[operation]()
        return value if abs(value) <= 1000000000 else None
    return None


def deterministic_key(question):
    expected = _deterministic_value(question)
    if expected is None:
        return None
    if question["questionType"] == "TF":
        return "A" if expected == "True" else "B"
    matches = [chr(65 + index) for index, option in enumerate(question["options"])
               if _option_number(option) == expected]
    if len(matches) != 1:
        raise AssessmentValidationError(
            f"Question '{question['questionText']}' has no unique option for the computed answer."
        )
    return matches[0]


def deterministic_explanation(question):
    text = question["questionText"]
    lower = text.lower()
    if question["questionType"] == "TF" and "differential equation" in lower:
        statement = re.search(
            r"\bhas\s+(?:an?\s+)?(order|degree)\s+(?:of\s+)?\d+\s*\.?\s*$",
            lower,
        )
        if statement:
            measure = (_derivative_order(text) if statement.group(1) == "order"
                       else _derivative_degree(text))
            if measure is not None:
                return (f"The equation's {statement.group(1)} is {measure}: order is "
                        "the highest derivative, while degree is its exponent.")
    if question["questionType"] == "MCQ" and "order" in lower and (
        "differential equation" in lower or "derivative in the equation" in lower
    ):
        order = _derivative_order(text)
        if order is not None:
            return f"The highest derivative is order {order}; powers of x do not change the equation's order."
    if question["questionType"] == "MCQ" and "degree" in lower and (
        "differential equation" in lower or "derivative in the equation" in lower
    ):
        degree = _derivative_degree(text)
        if degree is not None:
            return f"The highest derivative is raised to power {degree}; powers of x do not determine degree."
    if question["questionType"] == "MCQ":
        value = _deterministic_value(question)
        if value is not None:
            return f"Evaluating the stated arithmetic expression gives {value}."
    if "degree" in lower and "order" in lower:
        if "can have" in lower:
            return "Degree and order can differ; a derivative of the stated order can be raised to the stated degree."
        return "Order is the highest derivative; degree is its exponent, so neither must equal or exceed the other."
    if "order" in lower and "integer" in lower:
        return "In the standard definition, order counts the highest derivative and is a positive integer."
    return "The answer was checked against a deterministic rule."


def repair_numeric_options(source):
    """Repair AI-authored numeric choices only when the answer is computable."""
    question = source.model_dump() if hasattr(source, "model_dump") else dict(source)
    if question.get("questionType") != "MCQ":
        return question
    expected = _deterministic_value(question)
    if expected is None:
        return question
    options = question.get("options") or []
    if len(options) != 4:
        return question
    matches = [index for index, option in enumerate(options)
               if _option_number(option) == expected]
    if len(matches) == 1 and len(set(str(option).casefold() for option in options)) == 4:
        return question
    if not isinstance(expected, Fraction):
        expected = Fraction(expected)
    values = [expected]
    positive_only = "order" in question["questionText"].lower() or "degree" in question["questionText"].lower()
    for distance in range(1, 5):
        for candidate in (expected - distance, expected + distance):
            if candidate not in values and (not positive_only or candidate > 0):
                values.append(candidate)
            if len(values) == 4:
                break
        if len(values) == 4:
            break
    if len(values) != 4:
        return question
    seed = int.from_bytes(hashlib.sha256(question["questionText"].encode()).digest()[:8], "big")
    random.Random(seed).shuffle(values)
    question["options"] = [str(value) for value in values]
    question["correctAnswer"] = chr(65 + values.index(expected))
    return question


def normalize_questions(raw_questions, mcq_count, tf_count, *,
                        preserve_provided_answers=False, allow_duplicate_questions=False):
    expected = mcq_count + tf_count
    if len(raw_questions) != expected:
        raise AssessmentValidationError(f"Generated {len(raw_questions)} questions; expected {expected}.")
    result = []
    for number, source in enumerate(raw_questions, 1):
        source = source.model_dump() if hasattr(source, "model_dump") else dict(source)
        kind = str(source.get("questionType") or "").upper().strip()
        text = _clean_text(source.get("questionText"))
        options = [clean_option_label(option, index)
                   for index, option in enumerate(source.get("options") or [])]
        answer = str(source.get("correctAnswer") or "").upper().strip()
        if kind not in ("MCQ", "TF") or not text:
            raise AssessmentValidationError(f"Question {number} has an invalid type or empty text.")
        if preserve_provided_answers and not answer:
            raise AssessmentValidationError(
                f"Question {number} has no supplied answer key. Add its answer to the source."
            )
        if kind == "MCQ":
            if len(options) != 4 or len(set(option.casefold() for option in options)) != 4 or not all(options):
                raise AssessmentValidationError(f"Question {number} needs four distinct MCQ options.")
            if answer not in "ABCD" or re.search(r"\btrue\s+or\s+false\b", text, re.I):
                raise AssessmentValidationError(f"Question {number} is not a valid MCQ.")
            if {option.casefold() for option in options} == {"true", "false"}:
                raise AssessmentValidationError(f"Question {number} is True/False, not MCQ.")
        else:
            if [option.casefold() for option in options] != ["true", "false"] or answer not in "AB":
                raise AssessmentValidationError(f"Question {number} needs True/False options and key A or B.")
        question = {
            "part": 1 if kind == "MCQ" else 2,
            "questionType": kind,
            "questionText": text,
            "options": options,
            "correctAnswer": answer,
            "topicTag": _clean_text(source.get("topicTag")) or "General",
            "reasoning": _clean_text(source.get("reasoning")),
        }
        if source.get("verification"):
            question["verification"] = _clean_text(source["verification"])
        if not preserve_provided_answers:
            computed = deterministic_key(question)
            if computed:
                question["correctAnswer"] = computed
                question["reasoning"] = deterministic_explanation(question)
        result.append(question)
    actual = Counter(question["questionType"] for question in result)
    if actual["MCQ"] != mcq_count or actual["TF"] != tf_count:
        raise AssessmentValidationError(
            f"Generated {actual['MCQ']} MCQ and {actual['TF']} True/False; expected {mcq_count} MCQ and {tf_count} TF."
        )
    texts = [re.sub(r"\W+", "", question["questionText"].casefold()) for question in result]
    if not allow_duplicate_questions and len(set(texts)) != len(texts):
        raise AssessmentValidationError("Generated duplicate question text.")
    return [question for question in result if question["questionType"] == "MCQ"] + [
        question for question in result if question["questionType"] == "TF"]


def audit_payload(questions, start):
    return [{"number": start + index + 1, "questionType": question["questionType"],
             "questionText": question["questionText"], "options": question["options"]}
            for index, question in enumerate(questions)]


def apply_audit(questions, audit_items):
    by_number = {}
    for item in audit_items:
        item = item.model_dump() if hasattr(item, "model_dump") else dict(item)
        number = item.get("number")
        if number in by_number:
            raise AssessmentValidationError(f"Duplicate audit result for question {number}.")
        by_number[number] = item
    if set(by_number) != set(range(1, len(questions) + 1)):
        raise AssessmentValidationError("The answer-key audit omitted or added questions.")
    checked = []
    for number, question in enumerate(questions, 1):
        item = by_number[number]
        candidate = str(item.get("answer") or "?").upper().strip()
        if question["questionType"] == "TF":
            candidate = {"TRUE": "A", "FALSE": "B"}.get(candidate, candidate)
        allowed = "AB" if question["questionType"] == "TF" else "ABCD"
        computed = deterministic_key(question)
        if computed:
            candidate = computed
        elif not item.get("verified") or candidate not in allowed or not _clean_text(item.get("justification")):
            raise AssessmentValidationError(f"Question {number} has no independently verified unique answer.")
        verified = dict(question)
        verified["correctAnswer"] = candidate
        if candidate != question["correctAnswer"]:
            verified["reasoning"] = _clean_text(item.get("justification"))
        verified["verification"] = (deterministic_explanation(question) if computed
                                    else _clean_text(item.get("justification")))
        checked.append(verified)
    return checked


async def format_existing_questions(material, mcq_count, tf_count,
                                    on_progress=None, on_question=None, on_draft=None):
    """Transcribe instructor items without changing keys or discarding repeats."""
    from ai_instructions import (SYSTEM_EXISTING_QUESTIONS_FORMAT,
                                 get_existing_questions_prompt)
    from ai_service import (AssessmentResponse, HF_MODEL_REASONING, Question,
                            stream_structured_array)

    formatted = []
    source_occurrences = Counter()
    source_text = re.sub(r"\W+", "", material.casefold())
    for kind, count in (("MCQ", mcq_count), ("TF", tf_count)):
        for offset in range(0, count, 15):
            batch_count = min(15, count - offset)
            prompt = get_existing_questions_prompt(
                material, batch_count, batch_count if kind == "MCQ" else 0,
                batch_count if kind == "TF" else 0, start_index=offset + 1,
            )
            if on_progress:
                await on_progress(f"Formatting {kind} questions {offset + 1}-{offset + batch_count}...")
            batch = []

            async def show_draft(text, _item_index):
                if on_draft:
                    await on_draft(text, kind)

            async for raw in stream_structured_array(
                SYSTEM_EXISTING_QUESTIONS_FORMAT, prompt, AssessmentResponse,
                "questions", Question, HF_MODEL_REASONING,
                max_tokens=8000, temperature=0.0,
                on_partial=show_draft if on_draft else None,
                max_items=batch_count,
            ):
                batch.append(raw)
            if len(batch) != batch_count:
                raise AssessmentValidationError(
                    f"Found {len(batch)} of {batch_count} supplied {kind} questions "
                    f"at positions {offset + 1}-{offset + batch_count}. "
                    "Check the source and selected answer-sheet counts."
                )
            supplied = []
            for raw in batch:
                item = raw.model_dump() if hasattr(raw, "model_dump") else dict(raw)
                text_key = re.sub(r"\W+", "", str(item.get("questionText") or "").casefold())
                if text_key not in source_text:
                    raise AssessmentValidationError(
                        f"Formatted question {len(formatted) + len(supplied) + 1} "
                        "differs from the instructor's source. Keep the original wording."
                    )
                key = _source_answer_key(material, item.get("questionText") or "",
                                         source_occurrences[text_key])
                source_occurrences[text_key] += 1
                if key is None:
                    raise AssessmentValidationError(
                        f"Question {len(formatted) + len(supplied) + 1} has no readable "
                        "answer key in the source. Add an inline 'Answer: B' or a "
                        "numbered Answer Key section."
                    )
                item["correctAnswer"] = key
                supplied.append(item)
            # Validate formatting and keys without solving, replacing, or deduplicating.
            normalized = normalize_questions(
                supplied, batch_count if kind == "MCQ" else 0,
                batch_count if kind == "TF" else 0,
                preserve_provided_answers=True, allow_duplicate_questions=True,
            )
            for question in normalized:
                original_text = re.sub(r"\W+", "", question["questionText"].casefold())
                if original_text not in source_text:
                    raise AssessmentValidationError(
                        f"Formatted question {len(formatted) + 1} differs from the "
                        "instructor's source. Keep the original wording."
                    )
                if kind == "MCQ" and any(
                    re.sub(r"\W+", "", option.casefold()) not in source_text
                    for option in question["options"]
                ):
                    raise AssessmentValidationError(
                        f"Formatted question {len(formatted) + 1} contains a "
                        "choice missing from the instructor's source."
                    )
                formatted.append(question)
                if on_question:
                    await on_question(question, len(formatted))
    return normalize_questions(
        formatted, mcq_count, tf_count,
        preserve_provided_answers=True, allow_duplicate_questions=True,
    )


async def generate_verified_questions(material, mcq_count, tf_count,
                                      source_mode="topic", on_progress=None,
                                      on_question=None, on_draft=None):
    """Stream candidate questions, then audit and correct the complete draft.

    Returns only complete, type-correct assessments. Any unresolved key blocks
    completion instead of falling back to a guessed or placeholder answer.
    """
    source_mode = normalize_source_mode(source_mode)
    if mcq_count < 0 or tf_count < 0 or mcq_count + tf_count < 1:
        raise AssessmentValidationError("An assessment needs a positive question count.")
    if source_mode == "existing_questions" or _looks_like_existing_question_bank(
        material, mcq_count, tf_count,
    ):
        return await format_existing_questions(
            material, mcq_count, tf_count, on_progress, on_question, on_draft,
        )
    from ai_instructions import (
        SYSTEM_ANSWER_AUDIT, SYSTEM_ASSESSMENT_DESIGN,
        get_assessment_prompt,
    )
    from ai_service import (
        AnswerAuditItem, AnswerAuditResponse, AssessmentResponse,
        HF_MODEL_REASONING, Question, stream_structured_array,
    )

    accepted = []
    seen = set()
    rejected_texts = []
    for kind, count in (("MCQ", mcq_count), ("TF", tf_count)):
        done = 0
        attempts = 0
        stagnant = 0
        replacement_needed = False
        last_error = "No valid questions were returned."
        max_attempts = max(10, count * 2)
        # Keep a bounded exclusion list so repeated model output is replaced
        # instead of exhausting retries on the same duplicate item.
        while done < count and attempts < max_attempts and stagnant < 12:
            attempts += 1
            # Generate in chunks of 15 to avoid LLM output token limits (typically 4096).
            # 15 questions = ~3000 tokens, which fits comfortably and guarantees completion.
            batch_count = min(15, count - done)
            batch_mcq = batch_count if kind == "MCQ" else 0
            batch_tf = batch_count if kind == "TF" else 0
            prior = [question["questionText"] for question in accepted]
            prior.extend(rejected_texts[-20:])
            prompt = get_assessment_prompt(material, batch_count, batch_mcq > 0,
                                           batch_tf > 0, batch_mcq, batch_tf,
                                           source_mode, prior)
            if stagnant:
                prompt += f"\nThe previous attempt was rejected: {last_error}. Write different, unambiguous items."
            if replacement_needed:
                prompt += (f"\nThis is a replacement for rejected items. Write {batch_count} "
                           "new questions with distinct facts, scenarios, or calculations. "
                           "For numeric practice, change the inputs and recompute the keys. "
                           "Do not merely rephrase excluded questions.")
            if on_progress:
                await on_progress(f"Generating {kind} questions {done + 1}-{done + batch_count}...")
            before = done
            duplicate_in_batch = False
            try:
                proposed = []

                async def show_draft(text, _item_index):
                    if on_draft:
                        await on_draft(text, kind)

                async for raw in stream_structured_array(
                    SYSTEM_ASSESSMENT_DESIGN, prompt, AssessmentResponse,
                    "questions", Question,
                    HF_MODEL_REASONING,  # Use reasoning model to ensure large batches complete successfully
                    max_tokens=8000, temperature=min(0.3 + stagnant * 0.1, 0.8),
                    on_partial=show_draft if on_draft else None,
                    max_items=batch_count,
                ):
                    if len(proposed) >= batch_count:
                        continue
                    try:
                        raw = repair_numeric_options(raw)
                        item = normalize_questions([raw], 1 if kind == "MCQ" else 0,
                                                   1 if kind == "TF" else 0)[0]
                        key = re.sub(r"\W+", "", item["questionText"].casefold())
                        if key in seen or any(
                            key == re.sub(r"\W+", "", prior_item["questionText"].casefold())
                            for prior_item in proposed
                        ):
                            duplicate_in_batch = True
                            if item["questionText"] not in rejected_texts:
                                rejected_texts.append(item["questionText"])
                            raise AssessmentValidationError("Duplicate question")
                        proposed.append(item)
                        accepted.append(item)
                        seen.add(key)
                        done += 1
                        if on_question:
                            await on_question(item, len(accepted))
                    except AssessmentValidationError as exc:
                        last_error = str(exc)
            except Exception as exc:
                last_error = f"{type(exc).__name__}: {exc}"
            replacement_needed = duplicate_in_batch or done == before
            if done == before:
                stagnant += 1
                if on_progress:
                    await on_progress(f"No verifiable items in this batch: {last_error}. Retrying...")
            else:
                stagnant = 0
                if on_progress:
                    await on_progress(f"Accepted {done}/{count} {kind} questions.")
        if done != count:
            raise AssessmentValidationError(
                f"Could not draft {count} distinct {kind} questions; drafted {done}. Last issue: {last_error}"
            )

    questions = normalize_questions(accepted, mcq_count, tf_count)
    if on_progress:
        await on_progress("Checking final answers...")
    for question in questions:
        if deterministic_key(question) is not None:
            question["verification"] = deterministic_explanation(question)

    async def replace_question(index, reason):
        original = questions[index]
        kind = original["questionType"]
        excluded = [item["questionText"] for item in questions] + rejected_texts[-20:]
        for attempt in range(8):
            candidate = None
            prompt = get_assessment_prompt(material, 1, kind == "MCQ", kind == "TF",
                                           kind == "MCQ", kind == "TF", source_mode, excluded)
            prompt += (f"\nReplace this ambiguous item: {original['questionText']}. "
                       f"Issue: {reason}. Provide a distinct, verifiable question and answer.")
            try:
                async for raw in stream_structured_array(
                    SYSTEM_ASSESSMENT_DESIGN, prompt, AssessmentResponse,
                    "questions", Question,
                    HF_MODEL_REASONING,
                    max_tokens=2000, temperature=min(0.3 + attempt * 0.05, 0.6),
                    max_items=1,
                ):
                    raw = repair_numeric_options(raw)
                    candidate = normalize_questions([raw], 1 if kind == "MCQ" else 0, 1 if kind == "TF" else 0)[0]
                    key = re.sub(r"\W+", "", candidate["questionText"].casefold())
                    if any(key == re.sub(r"\W+", "", text.casefold()) for text in excluded):
                        continue
                    if deterministic_key(candidate) is not None:
                        candidate["verification"] = deterministic_explanation(candidate)
                    else:
                        audit_items = []
                        async for item in stream_structured_array(
                            SYSTEM_ANSWER_AUDIT,
                            "Independently check this replacement question. Proposed key omitted. "
                            "Mark ambiguous items unverified.\n"
                            + json.dumps(audit_payload([candidate], 0), ensure_ascii=False),
                            AnswerAuditResponse, "items", AnswerAuditItem,
                            HF_MODEL_REASONING, max_tokens=1200, temperature=0.0,
                        ):
                            audit_items.append(item)
                        candidate = apply_audit([candidate], audit_items)[0]
                    questions[index] = candidate
                    if on_question:
                        await on_question(candidate, index + 1)
                    return
            except AssessmentValidationError as exc:
                reason = str(exc)
            except Exception as exc:
                reason = f"{type(exc).__name__}: {exc}"
            if candidate is not None and candidate["questionText"] not in excluded:
                excluded.append(candidate["questionText"])
        raise AssessmentValidationError(
            f"Could not verify a replacement for question {index + 1}: {reason}"
        )

    audit_targets = [(index, question) for index, question in enumerate(questions)
                     if "verification" not in question]
    for offset in range(0, len(audit_targets), 8):
        group = audit_targets[offset:offset + 8]
        items = []
        for attempt in range(2):
            try:
                items.clear()
                async for item in stream_structured_array(
                    SYSTEM_ANSWER_AUDIT,
                    "Independently check each item; proposed keys are omitted. "
                    "Mark ambiguous questions unverified.\n"
                    + json.dumps(audit_payload([question for _, question in group], 0),
                                 ensure_ascii=False),
                    AnswerAuditResponse, "items", AnswerAuditItem,
                    HF_MODEL_REASONING, max_tokens=4200, temperature=0.0,
                ):
                    items.append(item.model_dump() if hasattr(item, "model_dump") else dict(item))
                if len({item["number"] for item in items}) == len(group):
                    break
            except Exception:
                if attempt == 1:
                    raise
        by_number = {item["number"]: item for item in items}
        for local_number, (index, question) in enumerate(group, 1):
            audit = by_number.get(local_number)
            try:
                if audit is None:
                    single_audit = []
                    async for item in stream_structured_array(
                        SYSTEM_ANSWER_AUDIT,
                        "Independently check this one question. Proposed key omitted. "
                        "Mark ambiguity unverified.\n"
                        + json.dumps(audit_payload([question], 0), ensure_ascii=False),
                        AnswerAuditResponse, "items", AnswerAuditItem,
                        HF_MODEL_REASONING, max_tokens=1200, temperature=0.0,
                    ):
                        single_audit.append(item)
                    if len(single_audit) != 1:
                        raise AssessmentValidationError("The final answer check omitted this item.")
                    audit = single_audit[0].model_dump() if hasattr(single_audit[0], "model_dump") else dict(single_audit[0])
                questions[index] = apply_audit([question], [{**audit, "number": 1}])[0]
            except AssessmentValidationError as exc:
                await replace_question(index, str(exc))

    return normalize_questions(questions, mcq_count, tf_count)
