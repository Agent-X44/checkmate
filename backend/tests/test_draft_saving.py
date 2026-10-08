import copy
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from httpx import ASGITransport, AsyncClient
import main

DRAFT = "00000000-0000-4000-8000-000000000001"
PAYLOAD = {"class_id": "class", "title": "Test", "draft_id": DRAFT,
           "template_id": "standard_30_questions", "questions": [
               {"questionText": "Which?", "questionType": "MCQ", "options": ["a", "b", "c", "d"], "correctAnswer": "B"}]}

class Query:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters = []; self.action = "select"; self.payload = None
    def select(self, *args): return self
    def limit(self, *args): return self
    def order(self, *args): return self
    def eq(self, key, value): self.filters.append((key, value)); return self
    def insert(self, payload): self.action = "insert"; self.payload = payload; return self
    def delete(self): self.action = "delete"; return self
    def execute(self):
        rows = self.db.rows[self.table]
        if self.action == "insert":
            if self.table == "exams" and self.db.legacy and "template_id" in self.payload:
                raise RuntimeError("PGRST204: template_id not found in schema cache")
            if self.table == "exams" and self.db.fail_exam:
                raise RuntimeError("database disconnected")
            if self.table == "questions" and self.db.fail_questions:
                raise RuntimeError("question insertion failed")
            values = self.payload if isinstance(self.payload, list) else [self.payload]
            rows.extend(copy.deepcopy(values)); return SimpleNamespace(data=values)
        matches = [r for r in rows if all(r.get(k) == v for k, v in self.filters)]
        if self.action == "delete":
            self.db.rows[self.table] = [r for r in rows if r not in matches]
        return SimpleNamespace(data=copy.deepcopy(matches))

@pytest.fixture
def db(monkeypatch):
    value = SimpleNamespace(rows={"classes": [{"id": "class", "instructor_id": "teacher"}], "exams": [], "questions": []}, legacy=True, fail_questions=False, fail_exam=False)
    value.table = lambda name: Query(value, name)
    monkeypatch.setattr(main, "supabase", value)
    main.app.dependency_overrides[main.get_current_user] = lambda: SimpleNamespace(user=SimpleNamespace(id="teacher"))
    yield value
    main.app.dependency_overrides.pop(main.get_current_user, None)

async def post(payload=PAYLOAD):
    async with AsyncClient(transport=ASGITransport(app=main.app), base_url="http://test") as client:
        return await client.post("/save-draft", json=payload)

@pytest.mark.asyncio
@pytest.mark.parametrize("legacy", [True, False])
async def test_legacy_and_current_save_retry_is_same_draft(db, legacy):
    db.legacy = legacy
    assert (await post()).status_code == 200
    assert (await post()).status_code == 200
    assert len(db.rows["exams"]) == len(db.rows["questions"]) == 1
    assert ("template_id" in db.rows["exams"][0]) is not legacy
    assert db.rows["exams"][0]["is_approved"] is False
    assert "A. a" in db.rows["questions"][0]["question_text"]

@pytest.mark.asyncio
async def test_question_failure_removes_incomplete_draft(db):
    db.fail_questions = True
    response = await post()
    assert response.status_code == 503
    assert db.rows["exams"] == []
    db.fail_questions = False
    assert (await post()).status_code == 200

@pytest.mark.asyncio
async def test_access_and_validation_before_writes(db):
    db.rows["classes"][0]["instructor_id"] = "other"
    assert (await post()).status_code == 403
    db.rows["classes"][0]["instructor_id"] = "teacher"
    payload = copy.deepcopy(PAYLOAD); payload["questions"][0]["questionType"] = "Essay"
    assert (await post(payload)).status_code == 422
    assert db.rows["exams"] == []

@pytest.mark.asyncio
async def test_unrelated_error_not_retried_or_exposed(db):
    db.fail_exam = True
    response = await post()
    assert response.status_code == 503
    assert "database disconnected" not in response.text
    assert db.rows["exams"] == []

@pytest.mark.asyncio
async def test_different_template_not_silently_dropped(db):
    payload = copy.deepcopy(PAYLOAD); payload["template_id"] = "custom"
    assert (await post(payload)).status_code == 409
    assert db.rows["exams"] == []

@pytest.mark.asyncio
async def test_conflicting_retry_does_not_change_saved_questions(db):
    assert (await post()).status_code == 200
    before = copy.deepcopy(db.rows)
    payload = copy.deepcopy(PAYLOAD); payload["questions"][0]["correctAnswer"] = "A"
    assert (await post(payload)).status_code == 409
    assert db.rows == before

@pytest.mark.asyncio
async def test_unauthenticated_save_rejected(db):
    main.app.dependency_overrides.pop(main.get_current_user)
    assert (await post()).status_code == 401
    assert db.rows["exams"] == []
