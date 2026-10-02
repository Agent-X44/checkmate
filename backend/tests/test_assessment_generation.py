import asyncio
import json
import os
import sys
from types import SimpleNamespace

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from assessment_generation import (
    AssessmentValidationError,
    apply_audit,
    deterministic_key,
    generate_verified_questions,
    normalize_questions,
    repair_numeric_options,
    validate_distribution,
)


def _mcq(number, key="A"):
    return {
        "part": 1,
        "questionType": "MCQ",
        "questionText": f"What is {number} plus 0?",
        "options": [str(number), str(number + 1), str(number + 2), str(number + 3)],
        "correctAnswer": key,
        "topicTag": "Arithmetic",
        "reasoning": f"Adding zero leaves {number}.",
    }


def _patch_stream(monkeypatch, fake_generate):
    import ai_service

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        response = await fake_generate(system_prompt, user_prompt, schema_class,
                                       model_override, max_tokens, temperature)
        for index, item in enumerate(getattr(response, array_key), 1):
            if on_partial and array_key == "questions":
                text = item.questionText if hasattr(item, "questionText") else item["questionText"]
                await on_partial(text, index)
            yield item

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)


def _audit_count(user_prompt):
    return len(json.loads(user_prompt.rsplit("\n", 1)[-1]))


def test_requested_distribution_rejects_inconsistent_flags():
    with pytest.raises(AssessmentValidationError):
        validate_distribution(30, 30, 0, True, True)


def test_wrong_order_key_is_computed_from_derivative_not_power_of_x():
    question = {
        **_mcq(1, key="B"),
        "questionText": "What is the order of the differential equation dy/dx = 3x^2?",
        "options": ["1", "2", "3", "4"],
    }
    checked = normalize_questions([question], 1, 0)
    assert checked[0]["correctAnswer"] == "A"


def test_degree_key_is_computed_from_derivative_exponent_not_power_of_x():
    question = {
        **_mcq(1, key="A"),
        "questionText": "What is the degree of the differential equation (dy/dx)^2 = 3x^2?",
        "options": ["1", "2", "3", "4"],
    }
    checked = normalize_questions([question], 1, 0)
    assert checked[0]["correctAnswer"] == "B"


def test_derivative_in_equation_wording_is_checked_directly():
    question = {
        **_mcq(1, key="A"),
        "questionText": "What is the degree of the derivative in the equation (y'')^2 + y = 0?",
        "options": ["A. 1", "B. 2", "C. 3", "D. 4"],
    }
    checked = normalize_questions([question], 1, 0)
    assert checked[0]["correctAnswer"] == "B"


def test_arithmetic_with_grouped_numbers_is_computed_directly():
    question = {
        **_mcq(1, key="A"),
        "questionText": "What is the sum of 1,876 and 2,145?",
        "options": ["4,000", "4,020", "4,021", "4,022"],
    }
    checked = normalize_questions([repair_numeric_options(question)], 1, 0)
    assert checked[0]["options"][ord(checked[0]["correctAnswer"]) - 65] == "4021"


def test_true_false_equation_claim_uses_derivative_not_function_power():
    question = {
        "part": 2, "questionType": "TF",
        "questionText": "The differential equation y'' + 2y' + 3y^4 = 0 has a degree of 4.",
        "options": ["True", "False"], "correctAnswer": "A",
    }
    checked = normalize_questions([question], 0, 1)
    assert checked[0]["correctAnswer"] == "B"
    assert "degree is its exponent" in checked[0]["reasoning"]


def test_compound_equation_claim_is_not_partially_verified():
    question = {
        "questionType": "TF",
        "questionText": "The differential equation y'' + y = 0 has order 2 and degree 2.",
        "options": ["True", "False"],
    }
    assert deterministic_key(question) is None


def test_wrong_tf_claim_and_mixed_count_are_rejected():
    with pytest.raises(AssessmentValidationError):
        normalize_questions([_mcq(1), {
            "part": 2, "questionType": "TF", "questionText": "Two is even.",
            "options": ["True", "False"], "correctAnswer": "A",
        }], 2, 0)


def test_mixed_output_is_grouped_into_sequential_parts():
    mixed = normalize_questions([{
        "part": 2, "questionType": "TF", "questionText": "Two is even.",
        "options": ["True", "False"], "correctAnswer": "A",
    }, _mcq(1)], 1, 1)
    assert [question["questionType"] for question in mixed] == ["MCQ", "TF"]
    assert [question["part"] for question in mixed] == [1, 2]


def test_model_choice_labels_are_removed_without_changing_the_key():
    question = {
        **_mcq(1, key="C"),
        "questionText": "Which network notation is used?",
        "options": ["A. First", "B) Second", "C. C. Third", "D: Fourth"],
    }
    checked = normalize_questions([question], 1, 0)
    assert checked[0]["options"] == ["First", "Second", "Third", "Fourth"]
    assert checked[0]["correctAnswer"] == "C"


def test_existing_questions_keep_repeated_text_and_supplied_keys(monkeypatch):
    import ai_service

    calls = []
    supplied = [
        {**_mcq(1, key="A"), "options": ["A. 1", "B. 2", "C. 3", "D. 4"]},
        {**_mcq(1, key="B"), "options": ["A. 1", "B. 2", "C. 3", "D. 4"]},
        {"questionType": "TF", "questionText": "Two is even.",
         "options": ["True", "False"], "correctAnswer": "A"},
    ]

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        calls.append((system_prompt, user_prompt, array_key))
        assert "positions 1 through" in user_prompt
        assert "Already selected items to exclude" not in user_prompt
        items = supplied[:2] if "2 MCQ" in user_prompt else supplied[2:]
        for item in items:
            yield item

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    result = asyncio.run(generate_verified_questions(
        "1. What is 1 plus 0? A. 1 B. 2 C. 3 D. 4 Answer: B\n"
        "2. What is 1 plus 0? A. 1 B. 2 C. 3 D. 4 Answer: A\n"
        "3. Two is even. Answer: False",
        2, 1, source_mode="existing_questions",
    ))
    assert len(result) == 3
    assert [item["questionText"] for item in result[:2]] == [
        "What is 1 plus 0?", "What is 1 plus 0?",
    ]
    assert [item["correctAnswer"] for item in result] == ["B", "A", "B"]
    assert result[0]["options"] == ["1", "2", "3", "4"]
    assert all(item["part"] == (1 if item["questionType"] == "MCQ" else 2)
               for item in result)
    assert len(calls) == 2
    assert all(array_key == "questions" for _, _, array_key in calls)


def test_existing_questions_keep_duplicates_across_stream_batches(monkeypatch):
    import ai_service

    prompts = []

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        prompts.append(user_prompt)
        for _ in range(max_items):
            yield {**_mcq(1), "options": ["A. 1", "B. 2", "C. 3", "D. 4"]}

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    material = "\n".join(
        f"{number}. What is 1 plus 0? A. 1 B. 2 C. 3 D. 4 Answer: A"
        for number in range(1, 17)
    )
    result = asyncio.run(generate_verified_questions(
        material, 16, 0, source_mode="existing_questions",
    ))
    assert len(result) == 16
    assert len({question["questionText"] for question in result}) == 1
    assert all(question["correctAnswer"] == "A" for question in result)
    assert len(prompts) == 2
    assert "positions 16 through 16" in prompts[1]


@pytest.mark.parametrize("source_mode", ["existing-questions", "topic"])
def test_existing_questions_accepts_alias_or_detected_bank_with_repeated_items(
        monkeypatch, source_mode):
    import ai_service

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        assert "positions 1 through 2" in user_prompt
        yield {**_mcq(1, key="A"), "questionText": "What is 1 plus 0?",
               "options": ["A. 1", "B. 2", "C. 3", "D. 4"]}
        yield {**_mcq(1, key="A"), "questionText": "What is 1 plus 0?",
               "options": ["A. 1", "B. 2", "C. 3", "D. 4"]}

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    material = "\n".join([
        "1. What is 1 plus 0?",
        "A. 1",
        "B. 2",
        "C. 3",
        "D. 4",
        "Answer: A",
        "2. What is 1 plus 0?",
        "A. 1",
        "B. 2",
        "C. 3",
        "D. 4",
        "Answer: A",
    ])
    result = asyncio.run(generate_verified_questions(
        material, 2, 0, source_mode=source_mode,
    ))
    assert len(result) == 2
    assert all(question["questionText"] == "What is 1 plus 0?" for question in result)
    assert all(question["correctAnswer"] == "A" for question in result)


def test_existing_questions_with_missing_key_fail_without_replacement(monkeypatch):
    import ai_service

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        yield _mcq(1)

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    with pytest.raises(AssessmentValidationError, match="no readable answer key"):
        asyncio.run(generate_verified_questions(
            "What is 1 plus 0? A. 1 B. 2 C. 3 D. 4", 1, 0,
            source_mode="existing_questions",
        ))


def test_existing_questions_reject_rewritten_source_text(monkeypatch):
    import ai_service

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        yield {**_mcq(1), "questionText": "What is one plus zero?"}

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    with pytest.raises(AssessmentValidationError, match="differs from the instructor's source"):
        asyncio.run(generate_verified_questions(
            "What is 1 plus 0? A. 1 B. 2 C. 3 D. 4 Answer: A",
            1, 0, source_mode="existing_questions",
        ))


def test_existing_questions_apply_separate_numbered_answer_key(monkeypatch):
    import ai_service

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        yield {**_mcq(1, key="A"), "questionText": "Which number is prime?",
               "options": ["4", "6", "7", "8"]}

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    result = asyncio.run(generate_verified_questions(
        "1. Which number is prime?\nA. 4\nB. 6\nC. 7\nD. 8\n"
        "Answer Key\n1. C", 1, 0, source_mode="existing_questions",
    ))
    assert result[0]["correctAnswer"] == "C"


def test_independent_audit_corrects_wrong_proposed_key():
    questions = normalize_questions([{
        **_mcq(1, key="B"),
        "questionText": "Which planet is known as the red planet?",
        "options": ["Mars", "Venus", "Earth", "Jupiter"],
    }], 1, 0)
    checked = apply_audit(questions, [{
        "number": 1, "answer": "A", "verified": True,
        "justification": "Mars appears red because of iron oxide on its surface.",
    }])
    assert checked[0]["correctAnswer"] == "A"
    assert checked[0]["reasoning"] == "Mars appears red because of iron oxide on its surface."


def test_unverified_audit_does_not_supply_answer_key():
    questions = normalize_questions([{
        **_mcq(1),
        "questionText": "Which option best explains the event?",
        "options": ["Option one", "Option two", "Option three", "Option four"],
    }], 1, 0)
    with pytest.raises(AssessmentValidationError):
        apply_audit(questions, [{
            "number": 1, "answer": "B", "verified": False,
            "justification": "The question is ambiguous.",
        }])


def test_independent_tf_audit_accepts_equivalent_truth_word():
    questions = normalize_questions([{
        "part": 2, "questionType": "TF", "questionText": "Water boils at 100 C at sea level.",
        "options": ["True", "False"], "correctAnswer": "A",
    }], 0, 1)
    checked = apply_audit(questions, [{
        "number": 1, "answer": "True", "verified": True,
        "justification": "At standard atmospheric pressure, water boils at about 100 C.",
    }])
    assert checked[0]["correctAnswer"] == "A"


def test_thirty_mcq_generation_never_adds_tf(monkeypatch):
    import ai_service

    next_number = 1
    calls = []

    async def fake_generate(system_prompt, user_prompt, schema_class,
                            model_override=None, max_tokens=8192, temperature=0.3):
        nonlocal next_number
        calls.append(schema_class.__name__)
        if schema_class.__name__ == "AssessmentResponse":
            questions = [_mcq(number) for number in range(next_number, next_number + 5)]
            next_number += 5
            return SimpleNamespace(questions=questions)
        return SimpleNamespace(items=[{
            "number": number, "answer": "A", "verified": True,
            "justification": "The first option is the only correct result.",
        } for number in range(1, _audit_count(user_prompt) + 1)])

    _patch_stream(monkeypatch, fake_generate)
    result = asyncio.run(generate_verified_questions("Basic arithmetic", 30, 0))
    assert len(result) == 30
    assert all(question["part"] == 1 and question["questionType"] == "MCQ"
               for question in result)
    assert calls == ["AssessmentResponse"] * 6 + ["AnswerAuditResponse"] * 4


def test_invalid_items_are_replaced_without_discarding_verified_items(monkeypatch):
    import ai_service

    generation = 0
    async def fake_generate(system_prompt, user_prompt, schema_class,
                            model_override=None, max_tokens=8192, temperature=0.3):
        nonlocal generation
        if schema_class.__name__ == "AssessmentResponse":
            generation += 1
            if generation == 1:
                return SimpleNamespace(questions=[
                    _mcq(1), _mcq(2),
                    {"questionType": "TF", "questionText": "Two is even.",
                     "options": ["True", "False"], "correctAnswer": "A"},
                ])
            return SimpleNamespace(questions=[_mcq(3), _mcq(4), _mcq(5)])
        size = _audit_count(user_prompt)
        return SimpleNamespace(items=[{
            "number": number, "answer": "A", "verified": True,
            "justification": "Adding zero keeps the same value.",
        } for number in range(1, size + 1)])

    _patch_stream(monkeypatch, fake_generate)
    result = asyncio.run(generate_verified_questions("Basic arithmetic", 5, 0))
    assert len(result) == 5
    assert generation == 2
    assert all(question["questionType"] == "MCQ" for question in result)


def test_duplicate_batch_uses_focused_replacements(monkeypatch):
    generation_prompts = []

    async def fake_generate(system_prompt, user_prompt, schema_class,
                            model_override=None, max_tokens=8192, temperature=0.3):
        if schema_class.__name__ == "AssessmentResponse":
            generation_prompts.append(user_prompt)
            items = [[_mcq(1), _mcq(2), _mcq(2), _mcq(3), _mcq(3)],
                     [_mcq(4)], [_mcq(5)]]
            return SimpleNamespace(questions=items[len(generation_prompts) - 1])
        size = _audit_count(user_prompt)
        return SimpleNamespace(items=[{
            "number": number, "answer": "A", "verified": True,
            "justification": "The stated arithmetic answer is correct.",
        } for number in range(1, size + 1)])

    _patch_stream(monkeypatch, fake_generate)
    result = asyncio.run(generate_verified_questions("Basic arithmetic", 5, 0))

    assert len(result) == 5
    assert len({question["questionText"] for question in result}) == 5
    assert "Write exactly 2 questions" in generation_prompts[1]
    assert "replacement for rejected items" in generation_prompts[1]


def test_deterministic_questions_stream_without_second_model_call(monkeypatch):
    import ai_service

    calls = 0
    streamed = []

    async def fake_generate(system_prompt, user_prompt, schema_class,
                            model_override=None, max_tokens=8192, temperature=0.3):
        nonlocal calls
        calls += 1
        assert schema_class.__name__ == "AssessmentResponse"
        return SimpleNamespace(questions=[{
            "part": 1, "questionType": "MCQ",
            "questionText": f"What is the order of the differential equation y' + {i}y = 0?",
            "options": ["2", "3", "4", "5"],
            "correctAnswer": "B", "topicTag": "Differential equations",
            "reasoning": "The power on the variable was mistaken for order.",
        } for i in range(1, 6)])

    async def on_question(question, number):
        correct_index = ord(question["correctAnswer"]) - 65
        streamed.append((number, question["options"][correct_index]))

    _patch_stream(monkeypatch, fake_generate)
    result = asyncio.run(generate_verified_questions(
        "Differential equation order", 5, 0, on_question=on_question))
    assert calls == 1
    assert streamed == [(number, "1") for number in range(1, 6)]
    assert all(question["verification"] for question in result)


def test_first_verified_question_arrives_before_model_finishes_batch(monkeypatch):
    import ai_service

    streamed = []

    async def fake_stream(system_prompt, user_prompt, schema_class, array_key,
                          item_class, model_override=None, max_tokens=8192,
                          temperature=0.3, on_partial=None, max_items=None):
        assert array_key == "questions"
        for number in range(1, 6):
            assert len(streamed) == number - 1
            if on_partial:
                await on_partial(f"What is the sum of {number}", number)
            yield {
                "part": 1, "questionType": "MCQ",
                "questionText": f"What is the sum of {number} and 2?",
                "options": ["A. 1", "B. 2", "C. 3", "D. 4"],
                "correctAnswer": "B", "topicTag": "Arithmetic",
                "reasoning": "Add the two numbers.",
            }

    async def on_question(question, number):
        assert "verification" not in question
        streamed.append(number)

    monkeypatch.setattr(ai_service, "stream_structured_array", fake_stream)
    drafts = []

    async def on_draft(text, kind):
        drafts.append((text, kind))

    result = asyncio.run(generate_verified_questions(
        "Adding integers", 5, 0, on_question=on_question, on_draft=on_draft))
    assert len(result) == 5
    assert streamed == [1, 2, 3, 4, 5]
    assert all(question["verification"] for question in result)
    assert len(drafts) == 5
