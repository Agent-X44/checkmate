import os
import sys
import pytest
import json
from httpx import AsyncClient, ASGITransport

# Add parent directory to path so 'main' can be imported
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import main
from main import app

@pytest.mark.asyncio
async def test_read_root():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "online"


def test_legacy_double_labeled_choices_are_restored_once():
    row = {
        "question_type": "MCQ",
        "question_text": "Which answer?\nA. A. First\nB. B. Second\nC. C. Third\nD. D. Fourth",
    }
    restored = main._restored_question(row)
    assert restored["options"] == ["First", "Second", "Third", "Fourth"]
    assert main._stored_question_text({
        "questionType": "MCQ", "questionText": "Which answer?",
        "options": ["A. First", "B. Second", "C. Third", "D. Fourth"],
    }) == "Which answer?\nA. First\nB. Second\nC. Third\nD. Fourth"

@pytest.mark.asyncio
async def test_generate_exam_schema(monkeypatch):
    """The legacy JSON endpoint uses the same exact-count checked pipeline."""
    async def fake_generate(material, mcq_count, tf_count):
        assert (mcq_count, tf_count) == (2, 0)
        return [{"questionType": "MCQ", "correctAnswer": "A"}] * 2

    monkeypatch.setattr(main, "generate_verified_questions", fake_generate)
    test_payload = {
        "topic": "Python Testing",
        "question_count": 2,
        "class_id": "123e4567-e89b-12d3-a456-426614174000"
    }
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/generate-exam", json=test_payload)

    assert response.status_code == 200
    assert len(response.json()["questions"]) == 2


@pytest.mark.asyncio
async def test_stream_keeps_exact_requested_types_without_persisting(monkeypatch):
    async def fake_generate(material, mcq_count, tf_count, source_mode, report,
                            on_question, on_draft):
        assert (mcq_count, tf_count) == (30, 0)
        await on_draft("Question 1", "MCQ")
        await report("Checking answer keys...")
        questions = [{
            "part": 1, "questionType": "MCQ", "questionText": f"Question {i}?",
            "options": ["one", "two", "three", "four"],
            "correctAnswer": "A", "verification": "The first option is correct.",
        } for i in range(1, 31)]
        for number, question in enumerate(questions, 1):
            await on_question(question, number)
        return questions

    class NoDatabaseWrites:
        def table(self, name):
            raise AssertionError("Generation must not create a draft before instructor review")

    monkeypatch.setattr(main, "generate_verified_questions", fake_generate)
    monkeypatch.setattr(main, "supabase", NoDatabaseWrites())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/generate-exam-stream", data={
            "topic": "Differential equations", "class_id": "course-1",
            "question_count": "30", "mcq_count": "30", "tf_count": "0",
            "include_mcq": "true", "include_tf": "false",
        })
    events = [json.loads(line[6:]) for line in response.text.splitlines()
              if line.startswith("data: ")]
    assert response.status_code == 200
    assert events[-1]["type"] == "complete"
    assert len(events[-1]["questions"]) == 30
    streamed = [event for event in events if event["type"] == "question"]
    draft_events = [event for event in events if event["type"] == "draft"]
    assert draft_events == [{"type": "draft", "questionType": "MCQ", "text": "Question 1"}]
    assert events.index(draft_events[0]) < events.index(streamed[0])
    assert not any("Checking" in event.get("content", "")
                   for event in events if event["type"] == "progress")
    assert [event["number"] for event in streamed] == list(range(1, 31))
    assert all(event["question"]["verification"] for event in streamed)


@pytest.mark.asyncio
async def test_stream_rejects_type_count_mismatch():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/generate-exam-stream", data={
            "topic": "Differential equations", "class_id": "course-1",
            "question_count": "30", "mcq_count": "30", "tf_count": "0",
            "include_mcq": "true", "include_tf": "true",
        })
    assert response.status_code == 422

@pytest.mark.asyncio
async def test_resolve_sheet_not_found():
    """Sheet metadata is inaccessible without an instructor token."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/resolve-sheet/invalid-id")
    assert response.status_code == 401


def test_saved_question_preserves_options_and_sequence():
    source = {
        "questionText": "What is one plus one?", "questionType": "MCQ",
        "options": ["1", "2", "3", "4"],
    }
    stored = main._stored_question_text(source)
    restored = main._restored_question({
        "question_text": stored, "question_type": "MCQ",
    })
    assert restored["question_text"] == source["questionText"]
    assert restored["options"] == source["options"]

    base = 1_800_000_000_000
    ids = [main._ordered_question_id(index, base) for index in range(3)]
    assert ids == sorted(ids)
