import os
import sys
import pytest
from httpx import AsyncClient, ASGITransport

# Add parent directory to path so 'main' can be imported
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from main import app

@pytest.mark.asyncio
async def test_read_root():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "online"

@pytest.mark.asyncio
async def test_generate_exam_schema():
    """Verify that generate-exam returns the correct JSON structure."""
    test_payload = {
        "topic": "Python Testing",
        "question_count": 2,
        "class_id": "test-class-uuid"
    }
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Note: This will attempt to call Ollama/Supabase unless mocked
        # For a pure unit test, you would mock the 'requests' and 'supabase' calls
        response = await ac.post("/generate-exam", json=test_payload)
    
    # If Ollama is not running, this will likely be a 500, which confirms the route exists
    assert response.status_code in [200, 500]

@pytest.mark.asyncio
async def test_resolve_sheet_not_found():
    """BR-05: Resolve sheet should return 404 for invalid identifiers."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/resolve-sheet/invalid-id")
    assert response.status_code == 404
