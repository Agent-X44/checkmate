import asyncio
from unittest.mock import AsyncMock
import pytest
from analysis_cache import AnalysisCache, PreparationQueue, fingerprint
from cryptography.fernet import Fernet


@pytest.mark.asyncio
async def test_concurrent_views_share_one_ai_request():
    cache = AnalysisCache()
    started, finish = asyncio.Event(), asyncio.Event()
    calls = 0
    async def generate():
        nonlocal calls
        calls += 1
        started.set()
        await finish.wait()
        return {'source': 'ai', 'analysis': {'text': 'ready'}}
    first = asyncio.create_task(cache.get_or_create('class', 'v1', generate))
    await started.wait()
    second = asyncio.create_task(cache.get_or_create('class', 'v1', generate))
    await asyncio.sleep(0)
    finish.set()
    assert await first == await second
    assert calls == 1
    assert (await cache.get_or_create('class', 'v1', generate))['source'] == 'ai'
    assert calls == 1


@pytest.mark.asyncio
async def test_cache_survives_process_recreation_and_invalidates_changed_results(tmp_path):
    path = tmp_path / 'cache.sqlite3'
    key = Fernet.generate_key()
    create = AsyncMock(return_value={'source': 'ai', 'analysis': 'first'})
    await AnalysisCache(path, encryption_key=key).get_or_create('class', fingerprint({'score': 1}), create)
    restored = AnalysisCache(path, encryption_key=key)
    assert (await restored.get_or_create('class', fingerprint({'score': 1}), create))['analysis'] == 'first'
    assert create.await_count == 1
    create.return_value = {'source': 'ai', 'analysis': 'new'}
    assert (await restored.get_or_create('class', fingerprint({'score': 2}), create))['analysis'] == 'new'
    assert create.await_count == 2
    assert b'"analysis": "first"' not in path.read_bytes() and b'"analysis": "new"' not in path.read_bytes()


@pytest.mark.asyncio
async def test_fallback_is_retried_after_short_expiry(monkeypatch):
    import analysis_cache
    now = [1000]
    monkeypatch.setattr(analysis_cache.time, 'time', lambda: now[0])
    create = AsyncMock(return_value={'source': 'summary'})
    cache = AnalysisCache()
    await cache.get_or_create('class', 'v1', create)
    now[0] += 30
    await cache.get_or_create('class', 'v1', create)
    assert create.await_count == 1
    now[0] += 31
    create.return_value = {'source': 'ai'}
    assert (await cache.get_or_create('class', 'v1', create))['source'] == 'ai'
    assert create.await_count == 2


@pytest.mark.asyncio
async def test_force_refresh_and_failed_jobs_do_not_poison_cache():
    cache = AnalysisCache()
    create = AsyncMock(side_effect=RuntimeError('unavailable'))
    with pytest.raises(RuntimeError): await cache.get_or_create('class', 'v1', create)
    create.side_effect = None
    create.return_value = {'source': 'ai'}
    await cache.get_or_create('class', 'v1', create)
    await cache.get_or_create('class', 'v1', create, force=True)
    assert create.await_count == 3


@pytest.mark.asyncio
async def test_preparation_merges_scans_without_losing_new_scans_during_generation():
    entered, finish = asyncio.Event(), asyncio.Event()
    calls = []
    async def prepare(exam_id, ids, overview):
        calls.append((exam_id, set(ids), overview))
        if len(calls) == 1:
            entered.set()
            await finish.wait()
    queue = PreparationQueue(prepare, delay=0)
    queue.schedule('exam', ['sheet-1'])
    queue.schedule('exam', ['sheet-2'])
    await entered.wait()
    queue.schedule('exam', ['sheet-3'], overview=True)
    finish.set()
    await asyncio.gather(*list(queue.tasks.values()))
    assert calls == [('exam', {'sheet-1', 'sheet-2'}, False), ('exam', {'sheet-3'}, True)]
    assert not queue.pending and not queue.tasks


@pytest.mark.asyncio
async def test_active_ai_concurrency_and_cache_size_are_bounded():
    cache = AnalysisCache(max_entries=2, concurrency=2)
    active, peak = 0, 0
    async def generate():
        nonlocal active, peak
        active += 1
        peak = max(peak, active)
        await asyncio.sleep(.01)
        active -= 1
        return {'source': 'ai'}
    await asyncio.gather(*(cache.get_or_create(str(i), 'v1', generate) for i in range(6)))
    assert peak == 2
    assert len(cache.entries) == 2
