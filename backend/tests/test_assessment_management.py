"""Offline authorization and state-transition checks for assessment management."""
import copy
from types import SimpleNamespace

import pytest
from httpx import ASGITransport, AsyncClient
from test_result_analysis import Database, Query, main


class ManagementQuery(Query):
    def in_(self, key, values):
        self.filters.append((key, set(values)))
        return self

    def delete(self):
        self.action = 'delete'
        return self

    def execute(self):
        self.db.calls.append((self.table, self.action, self.filters, self.payload))
        if self.table == self.db.fail_table or (self.action == 'delete' and getattr(self.db, 'fail_delete', False)):
            raise RuntimeError('Database failure')
        rows = [row for row in self.db.rows[self.table] if all(
            row.get(key) in value if isinstance(value, set) else row.get(key) == value
            for key, value in self.filters)]
        if self.action == 'update':
            for row in rows:
                row.update(self.payload)
        elif self.action == 'delete':
            self.db.rows[self.table] = [row for row in self.db.rows[self.table] if row not in rows]
            if self.table == 'exams':
                ids = {row['id'] for row in rows}
                self.db.rows['questions'] = [row for row in self.db.rows['questions'] if row['exam_id'] not in ids]
        if self.bounds:
            rows = rows[self.bounds[0]:self.bounds[1]]
        return SimpleNamespace(data=copy.deepcopy(rows))


@pytest.fixture
def management(monkeypatch):
    db = Database()
    monkeypatch.setattr(db, 'table', lambda name: ManagementQuery(db, name))
    monkeypatch.setattr(main, 'supabase', db)
    user = SimpleNamespace(user=SimpleNamespace(id='teacher'))
    main.app.dependency_overrides[main.get_current_user] = lambda: user
    yield db, user
    main.app.dependency_overrides.clear()


async def request(method, path, data=None):
    async with AsyncClient(transport=ASGITransport(app=main.app, raise_app_exceptions=False), base_url='http://test') as client:
        return await client.request(method, path, json=data)


@pytest.mark.asyncio
@pytest.mark.parametrize('action', ['approve-exam', 'unapprove-exam', 'release-results', 'unrelease-results', 'delete-exam'])
@pytest.mark.parametrize('actor', ['student-1', 'other-teacher'])
async def test_only_class_instructor_can_manage(management, action, actor):
    db, user = management
    user.user.id = actor
    response = await request('DELETE' if action == 'delete-exam' else 'POST', f'/{action}/exam-1')
    assert response.status_code == 403
    assert all(call[1] == 'select' for call in db.calls)


@pytest.mark.asyncio
@pytest.mark.parametrize('action', ['unrelease-results', 'unapprove-exam'])
async def test_withdrawal_preserves_grades_and_hides_from_students(management, action):
    db, user = management
    db.rows['exams'][0].update(results_released=True, status='Published')
    before = copy.deepcopy(db.rows['grades'])
    assert (await request('POST', f'/{action}/exam-1')).status_code == 200
    exam = db.rows['exams'][0]
    assert not exam['results_released']
    assert exam['is_approved'] == (action == 'unrelease-results')
    assert exam['status'] == ('Ready' if action == 'unrelease-results' else 'Draft')
    assert db.rows['grades'] == before
    assert db.rows['answer_sheets']
    user.user.id = 'student-1'
    assert (await request('GET', '/my-exam-result/exam-1')).status_code == 404


@pytest.mark.asyncio
async def test_unapproved_cannot_release_until_approved_again(management):
    db, _ = management
    await request('POST', '/unapprove-exam/exam-1')
    assert (await request('POST', '/release-results/exam-1')).status_code == 409
    assert (await request('POST', '/approve-exam/exam-1')).status_code == 200
    assert (await request('POST', '/release-results/exam-1')).status_code == 200
    assert db.rows['exams'][0]['status'] == 'Published'


def add_draft(db, exam_id):
    db.rows['exams'].append({'id': exam_id, 'class_id': 'class-1', 'is_approved': False,
        'results_released': False, 'status': 'Draft', 'classes': {'instructor_id': 'teacher'}})
    db.rows['questions'].append({'id': f'q-{exam_id}', 'exam_id': exam_id})


@pytest.mark.asyncio
async def test_bulk_delete_deduplicates_and_cascades_only_selected_drafts(management):
    db, _ = management
    for exam_id in ['draft-1', 'draft-2', 'draft-3']:
        add_draft(db, exam_id)
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ['draft-1', 'draft-2', 'draft-1']})
    assert response.status_code == 200
    assert set(response.json()['deleted_ids']) == {'draft-1', 'draft-2'}
    assert {e['id'] for e in db.rows['exams']} == {'exam-1', 'draft-3'}
    assert all(q['exam_id'] not in {'draft-1', 'draft-2'} for q in db.rows['questions'])
    assert sum(call[1] == 'delete' for call in db.calls) == 1


@pytest.mark.asyncio
@pytest.mark.parametrize('invalid,status', [('exam-1', 409), ('missing', 404), ('foreign', 403)])
async def test_invalid_member_prevents_entire_selection_deletion(management, invalid, status):
    db, _ = management
    add_draft(db, 'draft-1')
    add_draft(db, 'foreign')
    db.rows['exams'][-1]['classes']['instructor_id'] = 'other-teacher'
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ['draft-1', invalid]})
    assert response.status_code == status
    assert all(call[1] == 'select' for call in db.calls)


@pytest.mark.asyncio
async def test_unapproved_exam_with_existing_sheets_is_protected(management):
    db, _ = management
    db.rows['exams'][0]['is_approved'] = False
    before = copy.deepcopy(db.rows)
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ['exam-1']})
    assert response.status_code == 409
    assert db.rows == before


@pytest.mark.asyncio
@pytest.mark.parametrize('ids', [[], ['draft'] * 101 + ['other']])
async def test_empty_or_over_limit_selection_rejected(management, ids):
    if ids:
        ids = [f'draft-{i}' for i in range(101)]
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ids})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_delete_failure_does_not_report_success(management):
    db, _ = management
    add_draft(db, 'draft-1')
    db.fail_delete = True
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ['draft-1']})
    assert response.status_code == 500
    assert any(e['id'] == 'draft-1' for e in db.rows['exams'])


@pytest.mark.asyncio
async def test_missing_authentication_cannot_manage(management):
    main.app.dependency_overrides.clear()
    for method, path, data in [
        ('POST', '/delete-draft-exams', {'exam_ids': ['exam-1']}),
        ('POST', '/unrelease-results/exam-1', None),
        ('POST', '/unapprove-exam/exam-1', None),
    ]:
        assert (await request(method, path, data)).status_code in (401, 403)


@pytest.mark.asyncio
async def test_concurrent_approval_is_excluded_and_reported(management, monkeypatch):
    db, _ = management
    add_draft(db, 'draft-1')
    add_draft(db, 'draft-2')
    execute = ManagementQuery.execute

    def approve_before_delete(query):
        if query.action == 'delete':
            db.rows['exams'][-1]['is_approved'] = True
        return execute(query)

    monkeypatch.setattr(ManagementQuery, 'execute', approve_before_delete)
    response = await request('POST', '/delete-draft-exams', {'exam_ids': ['draft-1', 'draft-2']})
    assert response.status_code == 200
    assert response.json()['deleted_ids'] == ['draft-1']
    assert any(e['id'] == 'draft-2' and e['is_approved'] for e in db.rows['exams'])
