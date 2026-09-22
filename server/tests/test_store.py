"""Durable cache tests.

The test that matters most is `test_a_restart_does_not_re_pay_for_reviews`: it is
the exact failure that motivated the database (a restart in the middle of the
2026-09-22 OTES session would have thrown away 238 paid-for results).
"""

from __future__ import annotations

import json
import sqlite3
import threading

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import Settings, get_settings
from app.main import _review_cache, app
from app.schemas import ReviewResult
from app.store import SCHEMA_VERSION, SqliteCache

REVIEW = {
    "requirement_id": "FR-03",
    "text": "The system shall respond quickly to every search request.",
    "section": "3.2",
}


def _cache(path, *, namespace: str = "review", max_entries: int = 100) -> SqliteCache[ReviewResult]:
    return SqliteCache(
        path,
        namespace=namespace,
        encode=ReviewResult.model_dump_json,
        decode=ReviewResult.model_validate_json,
        max_entries=max_entries,
    )


def _result(requirement_id: str = "FR-03", score: int = 6) -> ReviewResult:
    return ReviewResult(
        requirement_id=requirement_id,
        score=score,
        issues=[],
        model="test-model",
    )


def test_put_get_round_trips_the_model(tmp_path):
    cache = _cache(tmp_path / "cache.sqlite3")
    cache.put("k1", _result(score=7))
    got = cache.get("k1")
    assert got is not None
    assert got.score == 7
    assert got.requirement_id == "FR-03"
    assert cache.get("missing") is None
    assert len(cache) == 1
    assert cache.degraded is False


def test_a_new_instance_on_the_same_file_sees_the_old_rows(tmp_path):
    path = tmp_path / "cache.sqlite3"
    _cache(path).put("k1", _result(score=9))
    assert _cache(path).get("k1").score == 9


def test_namespaces_do_not_collide(tmp_path):
    path = tmp_path / "cache.sqlite3"
    reviews = _cache(path, namespace="review")
    diagrams = _cache(path, namespace="diagram")

    reviews.put("same-key", _result(score=4))
    assert diagrams.get("same-key") is None

    reviews.clear()
    assert len(reviews) == 0
    assert len(diagrams) == 0 or diagrams.degraded


def test_clear_removes_the_rows_from_disk_not_just_from_memory(tmp_path):
    path = tmp_path / "cache.sqlite3"
    cache = _cache(path)
    cache.put("k1", _result())
    cache.clear()
    assert len(cache) == 0
    assert _cache(path).get("k1") is None


def test_undecodable_payload_is_dropped_and_treated_as_a_miss(tmp_path):
    path = tmp_path / "cache.sqlite3"
    cache = _cache(path)
    cache.put("k1", _result())
    # Simulate schema drift: a row that no longer validates.
    conn = sqlite3.connect(path)
    conn.execute("UPDATE cache_entries SET payload = ? WHERE key = 'k1'", ('{"nope": 1}',))
    conn.commit()
    conn.close()

    assert cache.get("k1") is None, "a bad row must be a miss, never an exception"
    # ...and it is gone, so the next request can store a good one.
    assert len(cache) == 0


def test_pruning_evicts_the_coldest_entry(tmp_path):
    cache = _cache(tmp_path / "cache.sqlite3", max_entries=3)
    for index in range(4):
        cache.put(f"k{index}", _result(score=index))
    assert len(cache) == 3
    assert cache.get("k0") is None, "k0 was the coldest"
    assert cache.get("k3").score == 3


def test_reading_refreshes_recency_so_a_hit_is_not_the_next_victim(tmp_path):
    cache = _cache(tmp_path / "cache.sqlite3", max_entries=3)
    cache.put("k0", _result(score=0))
    cache.put("k1", _result(score=1))
    cache.put("k2", _result(score=2))
    # Touch k0 so it stops being the oldest, then overflow.
    assert cache.get("k0") is not None
    cache.put("k3", _result(score=3))

    assert cache.get("k1") is None, "k1 became the coldest after k0 was read"
    assert cache.get("k0") is not None


def test_a_newer_schema_is_refused_and_the_file_left_alone(tmp_path):
    path = tmp_path / "cache.sqlite3"
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE cache_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    conn.execute(
        "INSERT INTO cache_meta (key, value) VALUES ('schema_version', ?)",
        (str(SCHEMA_VERSION + 1),),
    )
    conn.commit()
    conn.close()

    cache = _cache(path)
    assert cache.degraded is True
    # A newer file must not be rewritten by an older build.
    conn = sqlite3.connect(path)
    version = conn.execute("SELECT value FROM cache_meta WHERE key = 'schema_version'").fetchone()[0]
    conn.close()
    assert version == str(SCHEMA_VERSION + 1)
    # ...and it still works, in memory.
    cache.put("k1", _result())
    assert cache.get("k1") is not None


def test_an_unusable_path_degrades_to_memory_without_failing(tmp_path):
    # A directory is not a database file: connect() fails, and the cache must
    # keep serving rather than take the proxy down with it.
    cache = _cache(tmp_path, max_entries=2)
    assert cache.degraded is True
    cache.put("k1", _result(score=5))
    assert cache.get("k1").score == 5
    cache.put("k2", _result())
    cache.put("k3", _result())
    assert len(cache) == 2, "the in-memory fallback still respects the cap"
    cache.clear()
    assert cache.get("k1") is None


def test_concurrent_writers_do_not_lose_or_corrupt_rows(tmp_path):
    cache = _cache(tmp_path / "cache.sqlite3", max_entries=1000)
    errors: list[BaseException] = []

    def writer(worker: int) -> None:
        try:
            for index in range(25):
                key = f"w{worker}-k{index}"
                cache.put(key, _result(requirement_id=key))
                assert cache.get(key) is not None
        except BaseException as exc:  # noqa: BLE001 - surfaced via the assert below
            errors.append(exc)

    threads = [threading.Thread(target=writer, args=(worker,)) for worker in range(8)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert errors == []
    assert len(cache) == 200


@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    _review_cache.clear()
    with TestClient(app) as c:
        yield c
    _review_cache.clear()
    app.dependency_overrides.clear()


def test_a_restart_does_not_re_pay_for_reviews(client, monkeypatch):
    """The whole point: results outlive the process that produced them."""
    first = client.post("/review", json=REVIEW).json()
    assert first["cached"] is False

    calls: list[str] = []

    class CountingProvider:
        name = "mock"

        async def generate_json(self, *, system, user, schema, image_b64=None):
            calls.append(user)
            raise AssertionError("a cached result must not reach the provider")

    monkeypatch.setattr(main_module, "build_provider", lambda _settings: CountingProvider())

    # A restart: brand-new connection, brand-new in-memory state, same file.
    restarted = _cache(_review_cache.path)
    monkeypatch.setattr(main_module, "_review_cache", restarted)

    second = client.post("/review", json=REVIEW).json()
    assert second["cached"] is True
    assert second["score"] == first["score"]
    assert second["issues"] == first["issues"]
    assert calls == []


def test_health_reports_the_cache_state(client):
    body = client.get("/health").json()
    assert body["cache"]["engine"] == "sqlite"
    assert body["cache"]["degraded"] is False
    assert body["cache"]["review_entries"] >= 0


def test_the_cache_file_is_valid_sqlite_with_the_rows_the_endpoint_wrote(client):
    reviewed = client.post("/review", json=REVIEW).json()
    conn = sqlite3.connect(_review_cache.path)
    rows = conn.execute("SELECT key, payload FROM cache_entries WHERE namespace = 'review'").fetchall()
    conn.close()

    assert rows, "the endpoint must leave the result on disk"
    payload = json.loads(rows[0][1])
    assert payload["requirement_id"] == "FR-03"
    assert payload["score"] == reviewed["score"]
    assert payload["issues"] == reviewed["issues"]
