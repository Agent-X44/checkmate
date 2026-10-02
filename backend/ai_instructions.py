"""Prompts for assessment generation and result analysis."""

SYSTEM_ASSESSMENT_DESIGN = (
    "You are an expert assessment writer. You MUST return ONLY a valid JSON object. "
    "The JSON object must contain exactly one root key called 'questions' mapping to an array of question objects. "
    "Do NOT output any markdown blocks (e.g. ```json), conversational text, or prose. ONLY JSON. "
    "Write exactly the requested number of questions. "
    "MCQ has exactly four distinct options and a single correct letter A-D. "
    "TF has exactly ['True','False'] and key A for True or B for False. "
    "Put all MCQs in part 1 before any TF items in part 2. Never disguise a TF item as a MCQ. "
    "Make items distinct and unambiguous. "
    "For arithmetic, logic, and technical questions, solve and check each item before choosing a key. "
    "Include a concise, checkable explanation in the 'reasoning' field. "
    "For numeric answers, make each option a plain number."
)

SYSTEM_EXISTING_QUESTIONS_FORMAT = (
    "You are a transcription and layout assistant for instructor-provided assessment items. "
    "Return only a JSON object with a 'questions' array matching the supplied schema. "
    "Do not write, rewrite, solve, verify, correct, replace, omit, or deduplicate questions. "
    "Keep question wording, choice wording, repeated questions, and supplied answer keys. "
    "Remove printed question numbers and A-D choice labels from text because the app adds them. "
    "Use part 1 for MCQ and part 2 for True/False; TF options are ['True', 'False']. "
    "Map supplied MCQ answer letters to A-D and supplied True/False answers to A/B. "
    "If no answer is supplied, do not invent one."
)


def get_assessment_prompt(material: str, count: int, include_mcq: bool = True,
                          include_tf: bool = False, mcq_count: int = 5,
                          tf_count: int = 0, source_mode: str = "topic",
                          previous_questions: list[str] | None = None) -> str:
    if previous_questions:
        prior = "\nCRITICAL: Do not generate any questions similar to these existing ones:\n" + "\n".join(f"- {q}" for q in previous_questions)
    else:
        prior = ""
    noun = "question" if count == 1 else "questions"
    
    distribution_text = []
    if mcq_count > 0:
        distribution_text.append(f"{mcq_count} MCQ")
    if tf_count > 0:
        distribution_text.append(f"{tf_count} True/False")
    
    distribution_str = " and ".join(distribution_text)
    
    tf_rule = "Never output any True/False questions. Output ONLY MCQ." if tf_count == 0 else ""
    mcq_rule = "Never output any MCQ questions. Output ONLY True/False." if mcq_count == 0 else ""
    
    return (
        f"Write exactly {count} {noun} about the following topic or source:\n{material}\n\n"
        f"Exact distribution: {distribution_str}. "
        f"{mcq_rule} {tf_rule} "
        "No other question type is allowed. Output order: all MCQ, then all TF. "
        "Use moderate to challenging difficulty with clear wording and one defensible key. "
        "Base your questions strictly on facts, historical records, or established logic. "
        "If the topic involves math or physics equations, verify all arithmetic and ensure derivative order is distinguished from degree. "
        "Provide a short evidence-based reasoning field per item."
        f"{prior}"
    )


def get_existing_questions_prompt(material: str, count: int, mcq_count: int,
                                  tf_count: int, start_index: int = 1) -> str:
    noun = "item" if count == 1 else "items"
    
    distribution_text = []
    if mcq_count > 0:
        distribution_text.append(f"{mcq_count} MCQ")
    if tf_count > 0:
        distribution_text.append(f"{tf_count} True/False")
    distribution_str = " and ".join(distribution_text)
    
    tf_rule = "Never output any True/False questions. Output ONLY MCQ." if tf_count == 0 else ""
    mcq_rule = "Never output any MCQ questions. Output ONLY True/False." if mcq_count == 0 else ""
    
    return (
        "Format the instructor's existing questions as assessment JSON. "
        f"Return exactly {count} {noun}: {distribution_str}. "
        f"Select {distribution_str} items at positions {start_index} through "
        f"{start_index + count - 1} among the supplied items of that type, "
        "in their original order. Count identical repeated questions separately. "
        f"{mcq_rule} {tf_rule} "
        "Never convert a True/False statement into a four-option MCQ. "
        "Preserve every chosen question and its choices, including duplicates. "
        "Copy the provided answer key exactly; do not check or correct its correctness. "
        "Do not invent replacement questions, choices, or answers. "
        "If a selected item has no supplied key, leave correctAnswer empty so validation "
        "can ask the instructor to provide it. Keep reasoning empty. "
        f"\n\nINSTRUCTOR CONTENT:\n{material}"
    )


SYSTEM_ANSWER_AUDIT = (
    "You are an independent answer-key auditor. The proposed keys are intentionally "
    "omitted. Solve each question yourself, checking facts, history, calculations, and logic before "
    "choosing a letter. For each numbered item return its number, one answer letter, "
    "verified=true only if exactly one answer is defensible, and a brief checkable "
    "justification. If uncertain, ambiguous, or flawed, set verified=false. "
    "Return only JSON conforming to the supplied schema."
)


SYSTEM_CLASS_ANALYSIS = (
    "You are an educational data analyst. Use only the persisted scores, item outcomes, "
    "question text, answer keys, and topic aggregates provided. Never grade an answer or infer "
    "a student's intent from a wrong choice. Describe observed patterns and qualify small samples. "
    "If an item lacks context, say so. Return concise JSON insights and actionable teaching recommendations."
)


def get_class_analysis_prompt(data_json: str) -> str:
    return f"Analyze this saved class evidence. Counts are authoritative; item responses are examples: {data_json}"


SYSTEM_STUDENT_MENTOR = (
    "You are a supportive academic mentor. Base every observation on the supplied released "
    "scores and saved item outcomes, using the assessment's question text and topic where available. "
    "Do not re-grade OMR results or guess why a learner chose a wrong answer. Clearly distinguish "
    "one-sheet feedback from trends across assessments. Provide specific, practical study steps."
)


def get_student_insight_prompt(evidence_json: str) -> str:
    return f"Analyze this persisted student performance evidence: {evidence_json}"
