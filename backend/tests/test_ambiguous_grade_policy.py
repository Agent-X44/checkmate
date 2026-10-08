import pytest
from test_short_sheet_codes import request, short_sheet_db


@pytest.mark.asyncio
@pytest.mark.parametrize('marks', [
    {'isAmbiguous': True},
    {'isAmbiguous': False, 'multipleAnswers': ['A', 'B']},
])
async def test_ambiguous_answer_cannot_be_saved_as_correct(short_sheet_db, marks):
    db, _ = short_sheet_db
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [
            {'sheet_id': 'CM-8K9P2X8Q', 'score': 1, 'total': 1,
             'answers': [{'answer': 'A', 'isCorrect': True, **marks}]},
        ],
    })
    assert response.status_code == 422
    assert all(call[1] == 'select' for call in db.calls)


@pytest.mark.asyncio
async def test_ambiguous_answer_saves_with_zero_credit_and_mark_evidence(short_sheet_db):
    db, _ = short_sheet_db
    answer = {'answer': None, 'isCorrect': False, 'isAmbiguous': True,
              'multipleAnswers': ['A', 'B']}
    response = await request('POST', '/batch-save-grades', {
        'exam_id': 'exam-1', 'results': [
            {'sheet_id': 'CM-8K9P2X8Q', 'score': 0, 'total': 1,
             'answers': [answer]},
        ],
    })
    assert response.status_code == 200
    assert db.rows['grades'][0]['score'] == 0
    assert db.rows['grades'][0]['answers'] == [answer]
