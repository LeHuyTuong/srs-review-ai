"""Offline sync — POST /sync/push + GET /sync/pull.

Each test asserts the SHAPE of what came back (result per op, the current row,
the pulled record), not just a status code: a push that answers 200 while
storing nothing is the failure this suite exists to catch.
"""

from __future__ import annotations

import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.core.firebase_auth import verify_firebase_token
from app.infrastructure.sync_store import MAX_REMEMBERED_OPS, SyncOp, SyncStore, SyncUnavailable
from app.main import app


@pytest.fixture()
def env(tmp_path, monkeypatch):
    from app import main as main_mod

    store = SyncStore(tmp_path / "sync.sqlite3")
    monkeypatch.setattr(main_mod, "_sync_store", store)
    yield TestClient(app), store
    store.close()


def _as(uid: str):
    app.dependency_overrides[verify_firebase_token] = lambda: {"uid": uid}


def _op(op_id, record_id="c1", ts=1000, data=None, deleted=False, collection="courses"):
    return {
        "op_id": op_id,
        "collection": collection,
        "record_id": record_id,
        "deleted": deleted,
        "data": data if data is not None or deleted else {"id": record_id, "name": op_id},
        "client_ts": ts,
    }


def _push(client, ops, device="device-aaaa"):
    return client.post("/sync/push", json={"device_id": device, "ops": ops})


def test_push_then_pull_round_trips_the_record(env):
    client, _ = env
    res = _push(client, [_op("op-00000001", data={"id": "c1", "name": "Mobile"})])
    assert res.status_code == 200
    assert res.json()["results"] == [{"op_id": "op-00000001", "result": "accepted", "current": None}]

    pulled = client.get("/sync/pull", params={"since": 0}).json()
    assert pulled["has_more"] is False
    [change] = pulled["changes"]
    assert change["collection"] == "courses"
    assert change["record_id"] == "c1"
    assert change["data"] == {"id": "c1", "name": "Mobile"}
    assert change["device_id"] == "device-aaaa"
    assert pulled["cursor"] == change["seq"]
    assert client.get("/sync/pull", params={"since": pulled["cursor"]}).json()["changes"] == []


def test_resent_op_is_duplicate_and_applied_once(env):
    client, _ = env
    _push(client, [_op("op-00000001", data={"id": "c1", "name": "A"})])
    again = _push(client, [_op("op-00000001", data={"id": "c1", "name": "CHANGED"})]).json()
    [result] = again["results"]
    assert result["result"] == "duplicate"
    assert result["current"]["data"] == {"id": "c1", "name": "A"}
    assert len(client.get("/sync/pull").json()["changes"]) == 1


def test_older_client_ts_is_stale_and_returns_server_copy(env):
    client, _ = env
    _push(client, [_op("op-00000002", ts=2000, data={"id": "c1", "name": "newer"})], device="device-bbbb")
    [result] = _push(client, [_op("op-00000001", ts=1000, data={"id": "c1", "name": "older"})]).json()[
        "results"
    ]
    assert result["result"] == "stale"
    assert result["current"]["data"] == {"id": "c1", "name": "newer"}
    assert result["current"]["device_id"] == "device-bbbb"
    [row] = client.get("/sync/pull").json()["changes"]
    assert row["data"]["name"] == "newer"


def test_newer_write_wins_and_moves_cursor(env):
    client, _ = env
    _push(client, [_op("op-00000001", ts=1000)])
    first = client.get("/sync/pull").json()["cursor"]
    _push(client, [_op("op-00000002", ts=3000, data={"id": "c1", "name": "late"})], device="device-bbbb")
    later = client.get("/sync/pull", params={"since": first}).json()
    [row] = later["changes"]
    assert row["data"]["name"] == "late"
    assert later["cursor"] > first


def test_equal_timestamp_tie_breaks_on_device_id_both_ways(env):
    client, _ = env
    _push(client, [_op("op-00000001", ts=5000, data={"id": "c1", "name": "z"})], device="device-zzzz")
    [lost] = _push(client, [_op("op-00000002", ts=5000)], device="device-aaaa").json()["results"]
    assert lost["result"] == "stale"
    [won] = _push(client, [_op("op-00000003", ts=5000)], device="device-zzzz").json()["results"]
    assert won["result"] == "accepted"


def test_delete_is_a_tombstone_in_pull(env):
    client, _ = env
    _push(client, [_op("op-00000001", ts=1000)])
    _push(client, [_op("op-00000002", ts=2000, deleted=True, data={"ignored": True})])
    [row] = client.get("/sync/pull").json()["changes"]
    assert row["deleted"] is True
    assert row["data"] is None


def test_users_never_see_each_other(env):
    client, _ = env
    _as("alice")
    _push(client, [_op("op-00000001", data={"id": "c1", "name": "alice"})])
    _as("bob")
    assert client.get("/sync/pull").json()["changes"] == []
    [result] = _push(client, [_op("op-00000001", data={"id": "c1", "name": "bob"})]).json()["results"]
    assert result["result"] == "accepted"  # same op id, other user: not a duplicate
    _as("alice")
    [row] = client.get("/sync/pull").json()["changes"]
    assert row["data"]["name"] == "alice"


def test_pull_pages_with_has_more(env):
    client, _ = env
    _push(client, [_op(f"op-{i:08d}", record_id=f"r{i}", ts=i) for i in range(5)])
    page = client.get("/sync/pull", params={"limit": 2}).json()
    assert [c["record_id"] for c in page["changes"]] == ["r0", "r1"]
    assert page["has_more"] is True
    rest = client.get("/sync/pull", params={"since": page["cursor"], "limit": 10}).json()
    assert [c["record_id"] for c in rest["changes"]] == ["r2", "r3", "r4"]
    assert rest["has_more"] is False


@pytest.mark.parametrize(
    "bad",
    [
        {"device_id": "device-aaaa", "ops": [_op("op-00000001", collection="bad name")]},
        {"device_id": "device-aaaa", "ops": [_op("short")]},
        {"device_id": "device-aaaa", "ops": [{**_op("op-00000001"), "client_ts": -1}]},
        {"device_id": "device-aaaa", "ops": [{**_op("op-00000001"), "uid": "someone-else"}]},
        {"device_id": "device-aaaa", "ops": [_op(f"op-{i:08d}") for i in range(201)]},
    ],
)
def test_invalid_push_is_422_and_stores_nothing(env, bad):
    client, _ = env
    assert client.post("/sync/push", json=bad).status_code == 422
    assert client.get("/sync/pull").json()["changes"] == []


def test_missing_token_is_401(env):
    client, _ = env
    app.dependency_overrides.pop(verify_firebase_token)
    assert client.get("/sync/pull").status_code == 401
    assert _push(client, [_op("op-00000001")]).status_code == 401


def test_storage_failure_is_503_not_silent_success(env, monkeypatch):
    client, store = env

    def broken(*_a, **_k):
        raise SyncUnavailable("disk full")

    monkeypatch.setattr(store, "push", broken)
    monkeypatch.setattr(store, "pull", broken)
    assert _push(client, [_op("op-00000001")]).status_code == 503
    assert client.get("/sync/pull").status_code == 503


def test_records_survive_reopen(tmp_path):
    path = tmp_path / "sync.sqlite3"
    first = SyncStore(path)
    first.push("u", "device-aaaa", [SyncOp("op-00000001", "courses", "c1", False, {"id": "c1"}, 1)])
    first.close()
    again = SyncStore(path)
    assert again.pull("u", 0, 10)["changes"][0]["data"] == {"id": "c1"}
    [dup] = again.push("u", "device-aaaa", [SyncOp("op-00000001", "courses", "c1", False, {"id": "x"}, 9)])
    assert dup["result"] == "duplicate"
    again.close()


def test_op_memory_is_bounded_per_user(tmp_path):
    store = SyncStore(tmp_path / "sync.sqlite3")
    ops = [SyncOp(f"op-{i:08d}", "c", f"r{i}", False, {}, i) for i in range(MAX_REMEMBERED_OPS + 10)]
    store.push("u", "device-aaaa", ops)
    store.close()
    conn = sqlite3.connect(tmp_path / "sync.sqlite3")
    assert conn.execute("SELECT COUNT(*) FROM sync_ops WHERE uid = 'u'").fetchone()[0] == MAX_REMEMBERED_OPS
    oldest_kept = conn.execute("SELECT MIN(op_id) FROM sync_ops").fetchone()[0]
    conn.close()
    assert oldest_kept == "op-00000010"
