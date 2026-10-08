import copy
from unittest.mock import AsyncMock
import pytest
from test_result_analysis import setup, main, post, get


def provider(**kwargs):
    schema = kwargs['schema_class']
    if schema is main.ClassAnalysisResponse:
        return schema(insights='Saved class analysis', recommendations='Review oceans')
    if schema is main.StudentInsightResponse:
        return schema(performanceSummary='Saved personal feedback', strengths=['Capitals'],
                      learningGaps=['Oceans'], actionableSteps=['Review oceans'])
    return schema(performanceSummary='Saved released history', strengths=['Capitals'],
                  learningGaps=['Oceans'], actionableSteps=['Review oceans'])


@pytest.mark.asyncio
async def test_saved_results_prepare_feedback_and_subsequent_views_reuse_it(setup):
    db, user, ai = setup
    ai.side_effect = provider
    await main._prepare_analyses('exam-1', {'sheet-1'})
    assert ai.await_count == 2
    assert db.rows['grades'][0]['student_insight']['source'] == 'ai'
    assert (await post('/analyze-class', {'exam_id': 'exam-1'})).json()['analysis']['insights'] == 'Saved class analysis'
    assert (await post('/student-insight', {'exam_id': 'exam-1', 'sheet_id': 'sheet-1'})).status_code == 200
    assert ai.await_count == 2
    user.user.id = 'student-1'
    assert (await post('/student-insight', {'exam_id': 'exam-1', 'sheet_id': 'sheet-1'})).status_code == 403
    assert (await get('/my-exam-result/exam-1')).status_code == 404
    assert ai.await_count == 2


@pytest.mark.asyncio
async def test_class_cache_invalidates_when_saved_grade_changes_and_keeps_release_state_current(setup):
    db, _, ai = setup
    ai.side_effect = provider
    await post('/analyze-class', {'exam_id': 'exam-1'})
    await post('/analyze-class', {'exam_id': 'exam-1'})
    assert ai.await_count == 1
    db.rows['exams'][0]['results_released'] = True
    assert (await post('/analyze-class', {'exam_id': 'exam-1'})).json()['results_released'] is True
    assert ai.await_count == 1
    db.rows['grades'][0]['score'] = 0
    db.rows['grades'][0]['answers'][0]['isCorrect'] = False
    assert (await post('/analyze-class', {'exam_id': 'exam-1'})).json()['metrics']['average_percentage'] == 0
    assert ai.await_count == 2


@pytest.mark.asyncio
async def test_grade_sync_queues_work_only_after_successful_persistence(setup):
    db, _, ai = setup
    def queued(exam_id, ids):
        assert db.rows['grades'][0]['score'] == 0
        assert exam_id == 'exam-1' and ids == ['sheet-1']
    main.preparation_queue.schedule.side_effect = queued
    response = await post('/batch-save-grades', {'exam_id': 'exam-1', 'results': [
        {'sheet_id': 'CM-ABC12345', 'score': 0, 'total': 2}]})
    assert response.status_code == 200
    main.preparation_queue.schedule.assert_called_once()
    ai.assert_not_awaited()
    main.preparation_queue.schedule.reset_mock()
    db.fail_table = 'grades'
    assert (await post('/batch-save-grades', {'exam_id': 'exam-1', 'results': [
        {'sheet_id': 'CM-ABC12345', 'score': 0, 'total': 2}]})).status_code == 500
    main.preparation_queue.schedule.assert_not_called()


@pytest.mark.asyncio
async def test_old_feedback_cannot_be_attached_to_a_replaced_grade(setup):
    db, _, ai = setup
    async def changed(**kwargs):
        db.rows['grades'][0]['score'] = 0
        db.rows['grades'][0]['answers'][0]['isCorrect'] = False
        return provider(**kwargs)
    ai.side_effect = changed
    response = await post('/student-insight', {'exam_id': 'exam-1', 'sheet_id': 'sheet-1'})
    assert response.status_code == 409
    assert not db.rows['grades'][0].get('student_insight')


@pytest.mark.asyncio
async def test_withdrawal_during_generation_still_blocks_personal_feedback(setup):
    db, user, ai = setup
    db.rows['exams'][0]['results_released'] = True
    user.user.id = 'student-1'
    async def withdrawn(**kwargs):
        db.rows['exams'][0]['results_released'] = False
        return provider(**kwargs)
    ai.side_effect = withdrawn
    assert (await post('/student-insight', {'exam_id': 'exam-1', 'sheet_id': 'sheet-1'})).status_code == 403


@pytest.mark.asyncio
async def test_release_prepares_personal_overviews_without_waiting_for_ai(setup):
    db, _, ai = setup
    response = await post('/release-results/exam-1', {})
    assert response.status_code == 200
    main.preparation_queue.schedule.assert_called_once_with('exam-1', [], overview=True)
    ai.assert_not_awaited()
    ai.side_effect = provider
    await main._prepare_analyses('exam-1', set(), overview=True)
    assert db.rows['grades'][0]['student_insight']['source'] == 'ai'
    assert any(call.kwargs['schema_class'] is main.StudentOverviewResponse for call in ai.call_args_list)
