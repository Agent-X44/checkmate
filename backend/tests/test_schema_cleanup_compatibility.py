"""Deletion remains usable after obsolete schema objects are retired."""

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
        self.deleting = False

    def select(self, columns="*"):
        return self

    def delete(self):
        self.deleting = True
        return self

    def eq(self, key, value):
        self.filters.append((key, value))
        return self

    def limit(self, count):
        return self

    def in_(self, key, values):
        self.filters.append((key, set(values)))
        return self

    def execute(self):
        matches = [row for row in self.db.rows[self.table]
                   if all(row.get(key) in value if isinstance(value, set) else row.get(key) == value
                          for key, value in self.filters)]
        if self.deleting:
            self.db.rows[self.table] = [row for row in self.db.rows[self.table]
                                       if row not in matches]
        return SimpleNamespace(data=copy.deepcopy(matches))


class CleanDatabase:
    def __init__(self):
        self.requested_tables = []
        self.rows = {
            "classes": [{"id": f"class-{i}"} for i in (1, 2)],
            "exams": [{"id": f"exam-{i}", "class_id": f"class-{i}"}
                      for i in (1, 2)],
            "questions": [{"id": f"question-{i}", "exam_id": f"exam-{i}"}
                          for i in (1, 2)],
            "answer_sheets": [{"id": f"sheet-{i}", "exam_id": f"exam-{i}"}
                              for i in (1, 2)],
            "grades": [{"id": f"grade-{i}", "sheet_id": f"sheet-{i}"}
                       for i in (1, 2)],
            "enrollments": [{"id": f"enrollment-{i}", "class_id": f"class-{i}"}
                            for i in (1, 2)],
            "learning_materials": [{"id": f"material-{i}", "class_id": f"class-{i}"}
                                   for i in (1, 2)],
        }

    def table(self, name):
        self.requested_tables.append(name)
        if name not in self.rows:
            raise RuntimeError(f"Relation {name} does not exist")
        return Query(self, name)


@pytest.mark.asyncio
@pytest.mark.parametrize("target", ["exam", "course"])
async def test_deletion_after_retiring_unused_insight_table(monkeypatch, target):
    db = CleanDatabase()
    monkeypatch.setattr(main, "supabase", db)
    path = "/delete-exam/exam-1" if target == "exam" else "/delete-course/class-1"
    before = copy.deepcopy(db.rows)
    if target == "exam":
        db.rows['exams'][0].update(is_approved=False, results_released=False,
                                  classes={'instructor_id': 'teacher'})
        before = copy.deepcopy(db.rows)
    else:
        # Course deletion is limited to the instructor who owns the course.
        db.rows['classes'][0]['instructor_id'] = 'teacher'
    monkeypatch.setitem(main.app.dependency_overrides, main.get_current_user,
                        lambda: SimpleNamespace(user=SimpleNamespace(id='teacher')))

    async with AsyncClient(transport=ASGITransport(app=main.app),
                           base_url="http://test") as client:
        response = await client.delete(path)

    if target == "exam":
        # Unapproving must not make historical sheets/grades deletable.
        assert response.status_code == 409
        assert db.rows == before
        assert "ai_insights" not in db.requested_tables
        return

    assert response.status_code == 200
    assert response.json() == {"status": "success"}
    assert "ai_insights" not in db.requested_tables
    for table in ("exams", "questions", "answer_sheets", "grades"):
        assert len(db.rows[table]) == 1
        assert db.rows[table][0]["id"].endswith("-2")

    for table in ("classes", "enrollments", "learning_materials"):
        if target == "course":
            assert len(db.rows[table]) == 1
            assert db.rows[table][0]["id"].endswith("-2")
        else:
            assert len(db.rows[table]) == 2
