"""Bounded, versioned AI cache and debounced preparation of saved results."""
import asyncio
import copy
import hashlib
import json
import logging
import sqlite3
import time
from collections import OrderedDict
from pathlib import Path
from weakref import WeakKeyDictionary
from cryptography.fernet import Fernet

logger = logging.getLogger(__name__)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str,
                                     separators=(",", ":")).encode()).hexdigest()


class AnalysisCache:
    def __init__(self, path=None, max_entries=256, concurrency=2, encryption_key=None):
        self.path = Path(path) if path and encryption_key else None
        self.cipher = Fernet(encryption_key) if encryption_key else None
        self.max_entries, self.concurrency = max_entries, concurrency
        self.entries, self.inflight = OrderedDict(), {}
        self.limiters = WeakKeyDictionary()
        if self.path:
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                with sqlite3.connect(self.path) as db:
                    db.execute("CREATE TABLE IF NOT EXISTS analysis_cache (key TEXT PRIMARY KEY, version TEXT, expires REAL, value TEXT)")
            except Exception as exc:
                logger.warning("Disk AI cache unavailable: %s", type(exc).__name__)
                self.path = None

    def _read(self, key, version):
        entry = self.entries.get(key)
        if not entry and self.path:
            try:
                with sqlite3.connect(self.path) as db:
                    row = db.execute("SELECT version, expires, value FROM analysis_cache WHERE key=?", (key,)).fetchone()
                if row:
                    entry = row[0], row[1], json.loads(self.cipher.decrypt(row[2].encode()).decode())
            except Exception:
                logger.warning("Could not read disk AI cache")
        if entry and entry[0] == version and entry[1] > time.time():
            self.entries[key] = entry
            self.entries.move_to_end(key)
            self._trim()
            return copy.deepcopy(entry[2])
        return None

    def _trim(self):
        while len(self.entries) > self.max_entries:
            self.entries.popitem(last=False)

    def _write(self, key, version, value):
        expiry = time.time() + (60 if value.get("source") == "summary" else 86400)
        self.entries[key] = version, expiry, copy.deepcopy(value)
        self.entries.move_to_end(key)
        self._trim()
        if self.path:
            try:
                with sqlite3.connect(self.path) as db:
                    db.execute("INSERT OR REPLACE INTO analysis_cache VALUES (?, ?, ?, ?)",
                               (key, version, expiry, self.cipher.encrypt(json.dumps(value).encode()).decode()))
                    db.execute("DELETE FROM analysis_cache WHERE expires < ?", (time.time(),))
                    db.execute("DELETE FROM analysis_cache WHERE key NOT IN (SELECT key FROM analysis_cache ORDER BY expires DESC LIMIT ?)", (self.max_entries,))
            except Exception:
                logger.warning("Could not persist disk AI cache")

    async def get_or_create(self, key, version, create, force=False):
        key = fingerprint(key)
        if not force:
            cached = self._read(key, version)
            if cached is not None:
                return cached
        loop = asyncio.get_running_loop()
        job_key = loop, key, version
        task = self.inflight.get(job_key)
        if task is None:
            limiter = self.limiters.setdefault(loop, asyncio.Semaphore(self.concurrency))

            async def run():
                async with limiter:
                    value = await create()
                    self._write(key, version, value)
                    return value

            task = asyncio.create_task(run())
            self.inflight[job_key] = task

            def finished(completed):
                if self.inflight.get(job_key) is completed:
                    self.inflight.pop(job_key, None)
                if not completed.cancelled():
                    completed.exception()  # Consume errors if a caller disconnected.

            task.add_done_callback(finished)
        return copy.deepcopy(await asyncio.shield(task))


class PreparationQueue:
    def __init__(self, prepare, delay=3):
        self.prepare, self.delay = prepare, delay
        self.pending, self.tasks = {}, {}

    def schedule(self, exam_id, sheet_ids, overview=False):
        loop = asyncio.get_running_loop()
        key = loop, exam_id
        pending = self.pending.setdefault(key, {"ids": set(), "overview": False, "changed": loop.time()})
        pending['ids'].update(sheet_ids)
        pending['overview'] |= overview
        pending['changed'] = loop.time()
        if key in self.tasks:
            return

        async def run():
            try:
                while key in self.pending:
                    await asyncio.sleep(self.delay)
                    current = self.pending.get(key)
                    if current is None:
                        return
                    if loop.time() - current['changed'] < self.delay:
                        continue
                    batch = self.pending.pop(key)
                    try:
                        await self.prepare(exam_id, batch['ids'], batch['overview'])
                    except Exception:
                        logger.exception("Analysis preparation failed for assessment %s", exam_id)
            finally:
                self.tasks.pop(key, None)
                self.pending.pop(key, None)

        self.tasks[key] = asyncio.create_task(run())
