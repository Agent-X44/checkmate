import sys
from pathlib import Path
from unittest.mock import Mock
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@pytest.fixture(autouse=True)
def isolated_analysis_jobs(monkeypatch):
    import main
    from analysis_cache import AnalysisCache
    # Each test owns its AI provider and database. Do not run delayed production
    # workers after those test fixtures have been dismantled.
    monkeypatch.setattr(main, 'analysis_cache', AnalysisCache())
    monkeypatch.setattr(main.preparation_queue, 'schedule', Mock())
