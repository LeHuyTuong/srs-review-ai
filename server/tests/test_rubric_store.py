"""The editable rubric: syllabus thresholds and grading weights (2026-09-25).

What these pin, in priority order:

1. **The weights rule survives editing.** A set that no longer sums to 1.0 is
   refused AND nothing is written — the store keeps serving the old scale. This
   is the one property worth more than the feature: a broken scale produces
   ordinary-looking scores that are simply wrong.
2. **An override is exactly what the caller sent.** One leaf, no more: a UI that
   saves the pass mark must not blank the use-case count.
3. **Prose is not editable and not fingerprinted.** `source` / `gate` /
   `provenance` explain WHY a number is what it is; letting a form rewrite them
   would let the justification be deleted while the number stayed.
4. **Edits survive a restart; the seed never overwrites them.**
5. **A broken database degrades to the seed instead of failing a review.**
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.main import _rubric, app
from app.rubric import load_rubric
from app.rubric_store import RubricStore


@pytest.fixture
def store(tmp_path) -> RubricStore:
    made = RubricStore(tmp_path / "rubric.sqlite3")
    yield made
    made.close()


def _weight_total(rubric: dict) -> float:
    return sum(float(c["weight"]) for c in rubric["quality_criteria"].values())


def test_the_seed_is_the_baseline(store: RubricStore) -> None:
    assert store.stats()["overrides"] == 0
    assert _weight_total(store.current()) == pytest.approx(1.0)
    assert store.current() == load_rubric()


def test_a_reweighting_is_applied_and_survives_a_restart(store: RubricStore) -> None:
    # Move 0.10 from `clear` to `testable` — the kind of edit a supervisor makes
    # when "verifiable" turns out to be the dominant failure.
    store.update(
        {
            "quality_criteria": {
                "clear": {"weight": 0.15},
                "testable": {"weight": 0.50},
            }
        }
    )
    store.close()

    reopened = RubricStore(store._path)
    try:
        rubric = reopened.current()
        assert rubric["quality_criteria"]["clear"]["weight"] == 0.15
        assert rubric["quality_criteria"]["testable"]["weight"] == 0.50
        # Untouched leaves keep their seed values.
        assert rubric["quality_criteria"]["complete"]["weight"] == 0.20
        assert _weight_total(rubric) == pytest.approx(1.0)
    finally:
        reopened.close()


def test_weights_that_do_not_sum_to_one_are_refused_and_nothing_is_written(
    store: RubricStore,
) -> None:
    before = store.current()
    with pytest.raises(ValueError, match="sum to 1.0"):
        store.update({"quality_criteria": {"clear": {"weight": 0.9}}})
    assert store.current() == before
    assert store.stats()["overrides"] == 0, "a refused edit must leave no trace"


def test_a_reweighting_is_atomic_or_it_is_refused(store: RubricStore) -> None:
    """The consequence of the sum-to-1.0 rule, pinned because it shapes the API.

    Changing ONE weight always breaks the total, so a legal reweighting has to
    send every weight it moves in ONE call. A caller that sends three and leaves
    the fourth stale is refused — which is the correct outcome, not a bug: the
    alternative is a rubric that validates and then means something else. The
    app's editor therefore submits all four together.
    """
    with pytest.raises(ValueError, match="sum to 1.0"):
        store.update({"quality_criteria": {"clear": {"weight": 0.20}}})
    assert store.stats()["overrides"] == 0

    moved = store.update(
        {
            "quality_criteria": {
                "clear": {"weight": 0.15},
                "testable": {"weight": 0.50},
            }
        }
    )
    assert _weight_total(moved) == pytest.approx(1.0)


@pytest.mark.parametrize(
    ("patch", "message"),
    [
        ({"thresholds": {"pass_mark": 12}}, "between 0 and 10"),
        ({"thresholds": {"pass_mark": 0}}, "between 0 and 10"),
        ({"quality_criteria": {"clear": {"weight": 0}}}, "between 0 and 1"),
        ({"deterministic_checks": {"uc_count": {"min": -1}}}, "not be negative"),
        (
            {"deterministic_checks": {"uc_size": {"min_transactions": 9, "max_transactions": 4}}},
            "must not exceed",
        ),
    ],
)
def test_range_checks_refuse_the_obvious_mistakes(store: RubricStore, patch: dict, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        store.update(patch)


def test_an_unknown_leaf_is_refused_rather_than_ignored(store: RubricStore) -> None:
    """A typo that silently did nothing would look exactly like a successful
    edit in the UI, which is worse than an error."""
    with pytest.raises(ValueError, match="not editable"):
        store.update({"thresholds": {"pass_mrk": 6}})
    with pytest.raises(ValueError, match="not editable"):
        store.update({"provenance": "because I said so"})


def test_prose_is_not_editable_and_not_fingerprinted(store: RubricStore) -> None:
    before = store.fingerprint()
    with pytest.raises(ValueError, match="not editable"):
        store.update({"deterministic_checks": {"uc_count": {"gate": "trust me"}}})
    assert store.fingerprint() == before


def test_fingerprint_moves_only_for_the_leaves_that_change_a_score(
    store: RubricStore,
) -> None:
    before = store.fingerprint()
    store.update({"thresholds": {"pass_mark": 6.0}})
    assert store.fingerprint() != before, "a pass-mark change makes every cached score a different question"

    stable = store.fingerprint()
    store.update({"thresholds": {"min_per_part": 2.5}})
    assert store.fingerprint() != stable

    # The fingerprint is in the review cache key, so a value that moves on every
    # restart would make the cache useless.
    fresh = RubricStore(store._path.parent / "second.sqlite3")
    try:
        assert fresh.stats()["overrides"] == 0
        assert fresh.fingerprint() != stable
    finally:
        fresh.close()


def test_reset_restores_the_seed(store: RubricStore) -> None:
    store.update({"thresholds": {"pass_mark": 7.0}})
    restored = store.reset()
    assert restored["thresholds"]["pass_mark"] == load_rubric()["thresholds"]["pass_mark"]
    assert store.stats()["overrides"] == 0


def test_an_unwritable_database_serves_the_seed(tmp_path) -> None:
    blocked = tmp_path / "blocked"
    blocked.mkdir()
    degraded = RubricStore(blocked)
    try:
        assert degraded.degraded is True
        assert _weight_total(degraded.current()) == pytest.approx(1.0)
        assert degraded.fingerprint()
        degraded.update({"thresholds": {"pass_mark": 6.0}})
        assert degraded.current()["thresholds"]["pass_mark"] == 6.0
    finally:
        degraded.close()


# ------------------------------------------------------------------- HTTP


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client
    _rubric.reset()


def test_get_rubric_serves_the_seed_and_says_how_many_overrides_exist(
    client: TestClient,
) -> None:
    body = client.get("/rubric").json()
    assert body["version"] == load_rubric()["version"]
    assert body["editable"]["overrides"] == 0
    assert "limits" in body, "the deployment limits must survive the merge"


def test_http_edit_then_read_then_reset(client: TestClient) -> None:
    saved = client.put(
        "/rubric",
        json={
            "deterministic_checks": {"uc_count": {"min": 25}},
            "thresholds": {"pass_mark": 6.0},
        },
    )
    assert saved.status_code == 200
    assert saved.json()["rubric"]["deterministic_checks"]["uc_count"]["min"] == 25
    assert saved.json()["rubric"]["thresholds"]["pass_mark"] == 6.0

    live = client.get("/rubric").json()
    assert live["deterministic_checks"]["uc_count"]["min"] == 25
    assert live["editable"]["overrides"] == 2

    reset = client.post("/rubric/reset")
    assert reset.status_code == 200
    assert reset.json()["stats"]["overrides"] == 0
    assert client.get("/rubric").json()["thresholds"]["pass_mark"] == 5.0


def test_http_refusals_are_422_and_change_nothing(client: TestClient) -> None:
    before = client.get("/rubric").json()
    assert client.put("/rubric", json={"thresholds": {"pass_mark": 42}}).status_code == 422
    assert (client.put("/rubric", json={"quality_criteria": {"clear": {"weight": 0.9}}})).status_code == 422
    assert client.put("/rubric", json={"nonsense": 1}).status_code == 422
    assert client.put("/rubric", json={}).status_code == 422
    after = client.get("/rubric").json()
    assert after["thresholds"] == before["thresholds"]
    assert after["quality_criteria"] == before["quality_criteria"]


def test_rubric_writes_need_the_app_token(client: TestClient) -> None:
    from app.config import get_settings

    class _WithToken:
        app_token = "secret"

    client.app.dependency_overrides[get_settings] = lambda: _WithToken()
    try:
        assert client.put("/rubric", json={"thresholds": {"pass_mark": 6}}).status_code == 401
        assert (
            client.put(
                "/rubric",
                json={"thresholds": {"pass_mark": 6}},
                headers={"X-App-Token": "secret"},
            ).status_code
            == 200
        )
    finally:
        client.app.dependency_overrides.clear()
        _rubric.reset()


def test_health_reports_the_rubric_state(client: TestClient) -> None:
    client.put("/rubric", json={"thresholds": {"warn_score": 7.0}})
    body = client.get("/health").json()
    assert body["rubric"]["overrides"] == 1
    assert body["rubric"]["degraded"] is False
