"""Endpoints that change course data or spend AI quota require the course instructor."""

import copy
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from httpx import ASGITransport, AsyncClient

# These tests never connect to the deployed database.
os.environ["SUPABASE_URL"] = ""
os.environ["SUPABASE_KEY"] = ""
os.environ["OPENROUTER_API_KEY"] = ""
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main


class Query:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters = []
        self.changes = None
        self.deleting = False

    def select(self, columns="*"):
        return self

    def update(self, values):
        self.changes = values
        return self

    def delete(self):
        self.deleting = True
        return self

    def eq(self, key, value):
        self.filters.append((key, value))
        return self

    def limit(self, count):
        return self

    def execute(self):
        rows = self.db.rows[self.table]
        matches = [row for row in rows
                   if all(row.get(key) == value for key, value in self.filters)]
        if self.changes is not None:
            for row in matches:
                row.update(self.changes)
        if self.deleting:
            self.db.rows[self.table] = [row for row in rows if row not in matches]
        return SimpleNamespace(data=copy.deepcopy(matches))


class RejectingAuth:
    def get_user(self, token):
        raise RuntimeError("invalid JWT")


class CourseDatabase:
    """One course taught by 'teacher', with one exam and one question."""

    def __init__(self):
        self.auth = RejectingAuth()
        self.rows = {
            "classes": [{"id": "class-1", "instructor_id": "teacher"}],
            "exams": [{"id": "exam-1", "class_id": "class-1",
                       "classes": {"instructor_id": "teacher"}}],
            "questions": [{"id": "question-1", "exam_id": "exam-1",
                           "question_text": "Original?", "options": ["one", "two"],
                           "correct_answer": "A"}],
            "answer_sheets": [], "grades": [], "enrollments": [],
            "learning_materials": [],
        }

    def table(self, name):
        return Query(self, name)


QUESTION_UPDATE = {"question_text": "Changed?", "options": ["x", "y"],
                   "correct_answer": "B"}
PROTECTED_REQUESTS = [
    ("post", "/generate-exam",
     {"json": {"topic": "Algebra", "question_count": 1, "class_id": "class-1"}}),
    ("post", "/generate-exam-stream",
     {"data": {"topic": "Algebra", "class_id": "class-1", "question_count": "1",
               "mcq_count": "1", "tf_count": "0",
               "include_mcq": "true", "include_tf": "false"}}),
    ("put", "/update-question/question-1", {"json": QUESTION_UPDATE}),
    ("delete", "/delete-course/class-1", {}),
]


@pytest.fixture
def db(monkeypatch):
    async def generation_must_not_start(*args, **kwargs):
        raise AssertionError("Generation started for a caller without access")

    database = CourseDatabase()
    monkeypatch.setattr(main, "supabase", database)
    monkeypatch.setattr(main, "generate_verified_questions", generation_must_not_start)
    return database


def sign_in(monkeypatch, user_id):
    monkeypatch.setitem(main.app.dependency_overrides, main.get_current_user,
                        lambda: SimpleNamespace(user=SimpleNamespace(id=user_id)))


async def send(method, path, **kwargs):
    async with AsyncClient(transport=ASGITransport(app=main.app),
                           base_url="http://test") as client:
        return await client.request(method.upper(), path, **kwargs)


@pytest.mark.asyncio
@pytest.mark.parametrize("method, path, kwargs", PROTECTED_REQUESTS)
async def test_requests_without_a_token_are_rejected(db, method, path, kwargs):
    before = copy.deepcopy(db.rows)

    response = await send(method, path, **kwargs)

    assert response.status_code in (401, 403)
    assert db.rows == before


@pytest.mark.asyncio
@pytest.mark.parametrize("method, path, kwargs", PROTECTED_REQUESTS)
async def test_requests_with_an_invalid_token_are_rejected(db, method, path, kwargs):
    before = copy.deepcopy(db.rows)

    response = await send(method, path,
                          headers={"Authorization": "Bearer not-a-session"}, **kwargs)

    assert response.status_code == 401
    assert db.rows == before


@pytest.mark.asyncio
@pytest.mark.parametrize("method, path, kwargs", PROTECTED_REQUESTS)
async def test_other_signed_in_users_are_refused(monkeypatch, db, method, path, kwargs):
    sign_in(monkeypatch, "someone-else")
    before = copy.deepcopy(db.rows)

    response = await send(method, path, **kwargs)

    assert response.status_code == 403
    assert db.rows == before


@pytest.mark.asyncio
async def test_instructor_updates_a_question_in_their_own_exam(monkeypatch, db):
    sign_in(monkeypatch, "teacher")

    response = await send("put", "/update-question/question-1", json=QUESTION_UPDATE)

    assert response.status_code == 200
    assert db.rows["questions"][0]["question_text"] == "Changed?"
    assert db.rows["questions"][0]["correct_answer"] == "B"


@pytest.mark.asyncio
async def test_updating_an_unknown_question_is_not_found(monkeypatch, db):
    sign_in(monkeypatch, "teacher")

    response = await send("put", "/update-question/missing", json=QUESTION_UPDATE)

    assert response.status_code == 404


@pytest.mark.asyncio
async def test_instructor_deletes_their_own_course(monkeypatch, db):
    sign_in(monkeypatch, "teacher")

    response = await send("delete", "/delete-course/class-1")

    assert response.status_code == 200
    assert db.rows["classes"] == []
    assert db.rows["exams"] == []
    assert db.rows["questions"] == []


@pytest.mark.asyncio
async def test_generation_for_an_unknown_course_is_not_found(monkeypatch, db):
    sign_in(monkeypatch, "teacher")

    response = await send("post", "/generate-exam", json={
        "topic": "Algebra", "question_count": 1, "class_id": "no-such-class"})

    assert response.status_code == 404
