import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from ai_service import _JsonArrayObjectParser


def test_stream_parser_emits_each_complete_question_before_array_ends():
    parser = _JsonArrayObjectParser("questions")
    assert parser.feed('{"questions": [{"questionText": "One \\"quoted\\"') == []
    assert parser.current_question_text() == 'One "quoted"'
    first = parser.feed(' question", "options": ["A", "B"]},')
    assert len(first) == 1
    assert first[0]["questionText"] == 'One "quoted" question'
    assert parser.feed(' {"questionText": "Second question"') == []
    assert parser.current_question_text() == "Second question"
    second = parser.feed('}]}')
    assert [item["questionText"] for item in second] == ["Second question"]
    parser.finish()
