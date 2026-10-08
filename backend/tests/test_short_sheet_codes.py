"""Offline regression checks for printed codes versus internal database keys."""
from types import SimpleNamespace

import pytest
from httpx import ASGITransport, AsyncClient
from test_result_analysis import Database, main


@pytest.fixture
def short_sheet_db(monkeypatch):
    db = Database()
    db.rows['answer_sheets'][0].update(
        sheet_identifier='CM-8K9P2X8Q',
        profiles={'name': 'Student'},
        exams={'classes': {'instructor_id': 'teacher'}},
    )
    monkeypatch.setattr(main, 'supabase', db)
    user = SimpleNamespace(user=SimpleNamespace(id='teacher'))
    main.app.dependency_overrides[main.get_current_user] = lambda: user
    yield db, user
    main.app.dependency_overrides.clear()


async def request(method, path, payload=None):
    async with AsyncClient(transport=ASGITransport(app=main.app), base_url='http://test') as client:
        return await client.request(method, path, json=payload)


@pytest.mark.asyncio
async def test_short_code_resolves_and_checks_existing_grade(short_sheet_db):
    resolved = await request('GET', '/resolve-sheet/CM-8K9P2X8Q')
    assert resolved.status_code == 200
    assert resolved.json()['student_name'] == 'Student'
    scanned = await request('GET', '/check-sheet-scanned/CM-8K9P2X8Q')
    assert scanned.json() == {'scanned': True}


@pytest.mark.asyncio
async def test_batch_maps_short_code_without_changing_sheet_identity(short_sheet_db):
    db, _ = short_sheet_db
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [
            {'sheet_id': 'CM-8K9P2X8Q', 'score': 1, 'total': 2,
             'answers': [{'answer': 'B', 'isCorrect': False, 'warpedImage': 'private'}]},
        ],
    })
    assert response.json() == {'status': 'success', 'saved_count': 1}
    assert db.rows['grades'][0]['sheet_id'] == 'sheet-1'
    assert db.rows['grades'][0]['answers'] == [{'answer': 'B', 'isCorrect': False}]
    assert db.rows['answer_sheets'][0]['student_id'] == 'student-1'


@pytest.mark.asyncio
@pytest.mark.parametrize('code,status', [
    ('CM-22222222', 404),
    ('123e4567-e89b-12d3-a456-426614174000', 422),
])
async def test_invalid_code_prevents_all_batch_writes(short_sheet_db, code, status):
    db, _ = short_sheet_db
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [
            {'sheet_id': 'CM-8K9P2X8Q', 'score': 1, 'total': 2},
            {'sheet_id': code, 'score': 1, 'total': 2},
        ],
    })
    assert response.status_code == status
    assert all(call[1] == 'select' for call in db.calls)


@pytest.mark.asyncio
async def test_save_failure_is_reported(short_sheet_db):
    db, _ = short_sheet_db
    db.fail_table = 'grades'
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [{'sheet_id': 'CM-8K9P2X8Q', 'score': 1, 'total': 2}],
    })
    assert response.status_code == 500


@pytest.mark.asyncio
async def test_other_instructor_cannot_resolve_or_save(short_sheet_db):
    db, user = short_sheet_db
    user.user.id = 'other-teacher'
    scanned = await request('GET', '/check-sheet-scanned/CM-8K9P2X8Q')
    assert scanned.status_code == 403
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [{'sheet_id': 'CM-8K9P2X8Q', 'score': 1, 'total': 2}],
    })
    assert response.status_code == 403
    assert all(call[1] == 'select' for call in db.calls)
