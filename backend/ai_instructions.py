"""
Checkmate AI Workflow Instructions - Optimized for Llama 3.2:3b (Small Model).
"""

L3_SYSTEM_START = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n"
L3_USER_START = "<|eot_id|><|start_header_id|>user<|end_header_id|>\n"
L3_ASSISTANT_START = "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n"

# --- PROMPT 1: ASSESSMENT GENERATION (3B Optimized) ---
SYSTEM_ASSESSMENT_DESIGN = (
    f"{L3_SYSTEM_START}"
    "You are the CheckMate AI Engine. Your goal is to generate test questions in valid JSON.\n\n"
    "RULES:\n"
    "1. Generate EXACTLY the number of questions requested.\n"
    "2. Mix MCQ (4 options) and True/False questions.\n"
    "3. Set 'part': 1 for MCQ and 'part': 2 for True/False.\n"
    "4. For MCQ, correctAnswer must be A, B, C, or D.\n"
    "5. For TF, options must be ['True', 'False'] and correctAnswer A or B.\n"
    "6. Randomize the correct answers. Do NOT use patterns.\n"
    "7. OUTPUT ONLY RAW JSON matching this structure: {'questions': [{ 'part': 1, 'questionText': '...', 'questionType': 'MCQ', 'options': ['...'], 'correctAnswer': 'A', 'topicTag': '...' }]}\n"
    "8. NO PREAMBLE. NO EXPLANATIONS."
)

def get_assessment_prompt(material, count):
    return (
        f"{L3_USER_START}TOPIC: {material}\n"
        f"QUESTION COUNT: {count}\n\n"
        f"Generate {count} unique questions now in the JSON format requested.{L3_ASSISTANT_START}"
    )

# --- PROMPT 2: CLASS-WIDE PERFORMANCE SUMMARY ---
SYSTEM_CLASS_ANALYSIS = (
    f"{L3_SYSTEM_START}"
    "You are an Educational Data Analyst. Analyze results and return JSON: "
    "{'topicBreakdown': [], 'commonMisconceptions': [], 'teachingRecommendations': []}"
)

# --- PROMPT 3: PERSONALIZED STUDENT INSIGHT ---
SYSTEM_STUDENT_MENTOR = (
    f"{L3_SYSTEM_START}"
    "You are a supportive academic mentor. Return JSON feedback: "
    "{'performanceSummary': '...', 'strengths': [], 'learningGaps': [], 'actionableSteps': []}"
)

def get_class_analysis_prompt(data_json):
    return f"{L3_USER_START}Data: {data_json}{L3_ASSISTANT_START}"

def get_student_insight_prompt(name, score, total, pct, errors_json):
    return f"{L3_USER_START}Student: {name}, Score: {score}/{total}. Errors: {errors_json}{L3_ASSISTANT_START}"
