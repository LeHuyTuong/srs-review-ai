"""The editable evaluation criteria (2026-09-25).

What these pin, in priority order:

1. **The CRUD is real.** A criterion added, edited, disabled or deleted through
   the store must actually change what the prompt says. A CRUD that only writes
   to a table nobody reads is worse than no CRUD, because the user believes they
   changed the review.
2. **The cache key follows the criteria.** Editing a criterion's wording must
   change the fingerprint, or the app keeps serving results produced under the
   old wording — the same class of bug the 11-part review cache key exists for.
3. **An edit survives a restart, and the seed never overwrites it.** A marking
   sheet that resets itself on every deploy is not editable.
4. **A broken database degrades, it does not fail.** Same contract as the cache:
   the review path must not 500 because a criteria write could not land.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.criteria import CriteriaStore, load_seed
from app.config import get_settings
from app.main import _criteria, app
from app.prompt import review_system_prompt
from app.rubric import load_rubric


@pytest.fixture
def store(tmp_path) -> CriteriaStore:
    made = CriteriaStore(tmp_path / "criteria.sqlite3")
    yield made
    made.close()


def test_seed_is_valid_and_ordered() -> None:
    seed = load_seed()
    assert len(seed) >= 10
    assert [row["order"] for row in seed] == sorted(row["order"] for row in seed)
    assert {"unit", "document"} <= {row["scope"] for row in seed}
    assert all(row["enabled"] for row in seed), "a disabled seed row would be invisible"


def test_list_seeds_once_and_then_survives_a_restart(store: CriteriaStore) -> None:
    first = store.list()
    assert first, "the seed must be applied on first use"
    edited = store.update(first[0]["id"], {"title": "Tiêu chí đã sửa"})
    assert edited is not None
    store.close()

    reopened = CriteriaStore(store._path)
    try:
        again = reopened.get(first[0]["id"])
        assert again is not None
        assert again["title"] == "Tiêu chí đã sửa", (
            "a restart must not revert the user's marking sheet"
        )
    finally:
        reopened.close()


def test_create_update_delete_round_trip(store: CriteriaStore) -> None:
    created = store.create(
        {
            "id": "house_style",
            "title": "Văn phong nhất quán",
            "what": "The same noun is spelled the same way everywhere.",
            "scope": "unit",
            "severity": "low",
            "order": 500,
        }
    )
    assert created["id"] == "house_style"
    assert store.get("house_style") is not None

    # Partial update: absent fields stay as they were.
    updated = store.update("house_style", {"severity": "high"})
    assert updated is not None
    assert updated["severity"] == "high"
    assert updated["title"] == "Văn phong nhất quán"

    assert store.delete("house_style") is True
    assert store.get("house_style") is None
    assert store.delete("house_style") is False, "deleting twice is a 404, not a crash"


def test_duplicate_id_is_refused(store: CriteriaStore) -> None:
    with pytest.raises(ValueError, match="already exists"):
        store.create({"id": "verifiable", "title": "Trùng", "what": "Trùng id seed"})


def test_validation_rejects_a_criterion_the_prompt_cannot_use(
    store: CriteriaStore,
) -> None:
    for payload in (
        {"id": "x", "title": "", "what": "w"},
        {"id": "x", "title": "t", "what": "  "},
        {"id": "x", "title": "t", "what": "w", "scope": "galaxy"},
        {"id": "x", "title": "t", "what": "w", "severity": "apocalyptic"},
    ):
        with pytest.raises(ValueError):
            store.create(payload)


def test_prompt_block_renders_the_enabled_rows_and_hides_the_rest(
    store: CriteriaStore,
) -> None:
    block = store.prompt_block("unit")
    assert "[unambiguous]" in block
    assert "document_consistency" not in block, (
        "a document-scope criterion must not be asked of a single requirement"
    )

    store.update("unambiguous", {"enabled": False})
    assert "[unambiguous]" not in store.prompt_block("unit")
    assert store.prompt_block("unit"), "other criteria remain"


def test_prompt_block_is_empty_when_a_scope_is_fully_disabled(
    store: CriteriaStore,
) -> None:
    for row in store.list():
        store.update(row["id"], {"enabled": False})
    assert store.prompt_block("unit") == ""


def test_fingerprint_tracks_exactly_what_the_prompt_renders(
    store: CriteriaStore,
) -> None:
    before = store.fingerprint()
    store.update("verifiable", {"what": "Now it demands a percentile."})
    assert store.fingerprint() != before, (
        "edited wording must invalidate the cached reviews that used the old text"
    )

    after_edit = store.fingerprint()
    store.update("verifiable", {"what": "Now it demands a percentile."})
    assert store.fingerprint() == after_edit, "the same rows must hash the same"

    store.update("traceable", {"enabled": False})
    assert store.fingerprint() != after_edit, "a toggle is part of the identity"

    # A field the prompt never renders must not churn the key: editing `source`
    # is documentation, and invalidating every cached review for it would train
    # users to distrust the cache.
    stable = store.fingerprint()
    store.update("verifiable", {"source": "internal note"})
    assert store.fingerprint() == stable


def test_reset_restores_the_seed(store: CriteriaStore) -> None:
    store.delete("verifiable")
    store.create({"id": "temporary", "title": "t", "what": "w"})
    restored = store.reset()
    assert any(row["id"] == "verifiable" for row in restored)
    assert not any(row["id"] == "temporary" for row in restored)
    assert store.get("verifiable") is not None


def test_an_unwritable_database_degrades_instead_of_failing(tmp_path) -> None:
    """The review path must not raise because criteria could not be persisted.

    A directory where the database file should be makes sqlite3.connect fail,
    which is the closest local stand-in for the read-only filesystem the cache
    already documents.
    """
    blocked = tmp_path / "blocked"
    blocked.mkdir()
    degraded = CriteriaStore(blocked)  # a directory, not a file
    try:
        assert degraded.degraded is True
        assert degraded.list(), "the seed must answer from memory"
        assert degraded.prompt_block("unit")
        assert degraded.fingerprint()
        created = degraded.create(
            {"id": "in_memory", "title": "t", "what": "w", "order": 900}
        )
        assert created["id"] == "in_memory"
        assert degraded.get("in_memory") is not None
    finally:
        degraded.close()


# ------------------------------------------------------------------- HTTP


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client
    _criteria.reset()


def test_get_criteria_returns_the_seed_with_stats(client: TestClient) -> None:
    body = client.get("/criteria").json()
    assert body["criteria"]
    assert body["stats"]["total"] == len(body["criteria"])
    assert body["stats"]["enabled"] >= 1


def test_http_crud_round_trip(client: TestClient) -> None:
    created = client.post(
        "/criteria",
        json={
            "id": "http_round_trip",
            "title": "Qua HTTP",
            "what": "A criterion created through the API.",
            "scope": "unit",
            "severity": "low",
            "order": 800,
        },
    )
    assert created.status_code == 201
    assert created.json()["criterion"]["id"] == "http_round_trip"

    updated = client.put("/criteria/http_round_trip", json={"enabled": False})
    assert updated.status_code == 200
    assert updated.json()["criterion"]["enabled"] is False

    listed = client.get("/criteria").json()["criteria"]
    assert any(row["id"] == "http_round_trip" and not row["enabled"] for row in listed)

    deleted = client.delete("/criteria/http_round_trip")
    assert deleted.status_code == 200
    assert client.get("/criteria").json()["stats"]["total"] == len(listed) - 1


def test_http_errors_use_the_project_shape(client: TestClient) -> None:
    assert client.put("/criteria/nope", json={"title": "x"}).status_code == 404
    assert client.delete("/criteria/nope").status_code == 404
    assert (
        client.post(
            "/criteria",
            json={"id": "verifiable", "title": "dup", "what": "dup"},
        ).status_code
        == 409
    )
    assert (
        client.post(
            "/criteria",
            json={"id": "bad id with spaces", "title": "t", "what": "w"},
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/criteria",
            json={"id": "ok", "title": "t", "what": "w", "scope": "galaxy"},
        ).status_code
        == 422
    )


def test_criteria_reads_and_writes_need_the_app_token(client: TestClient) -> None:
    """Reads are protected too: a shared proxy must not hand out its marking
    sheet to anyone who can reach the port."""

    class _WithToken:
        app_token = "secret"

    client.app.dependency_overrides[get_settings] = lambda: _WithToken()
    try:
        assert client.get("/criteria").status_code == 401
        assert (
            client.post(
                "/criteria", json={"id": "x", "title": "t", "what": "w"}
            ).status_code
            == 401
        )
        assert client.get("/criteria", headers={"X-App-Token": "secret"}).status_code == 200
    finally:
        client.app.dependency_overrides.clear()


def test_the_review_prompt_carries_the_stored_criteria(client: TestClient) -> None:
    """The end-to-end claim: what the user edits is what the model is told."""
    _criteria.update("verifiable", {"what": "SENTINEL-WORDING"})
    try:
        prompt = review_system_prompt(
            {**load_rubric(), "criteria_block": _criteria.prompt_block("unit")}
        )
        assert "SENTINEL-WORDING" in prompt
        assert "EVALUATION CRITERIA" in prompt
    finally:
        _criteria.reset()


def test_health_reports_the_criteria_state(client: TestClient) -> None:
    body = client.get("/health").json()
    assert "criteria" in body
    assert body["criteria"]["total"] >= 10
    assert body["criteria"]["document_scope"] >= 1, (
        "the flow/ordering family has to be reachable from the checklist"
    )