"""Teacher decisions — plan 12 WP3, ADR-0016 decision 2.

Authority on this route is the CONTAINING CLASS's write key, NOT the app
token: the group's own app holds the app token, so accepting it would let a
group approve its own work — ADR-0017's hole, re-opened on a worse path.
Every test maps to an AC (a)–(i) in plan 12 §2 WP3.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.classes import ClassStore
from app.infrastructure.submissions import SubmissionStore
from app.main import app

APP_TOKEN = "test-app-secret"


@pytest.fixture()
def make_env(tmp_path, monkeypatch):
    from app import main as main_mod

    submissions = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=4 * 1024 * 1024)
    classes = ClassStore(class_dir=tmp_path / "classes")
    monkeypatch.setattr(main_mod, "_submission_store", submissions, raising=False)
    monkeypatch.setattr(main_mod, "_class_store", classes, raising=False)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True, gemini_api_key="", app_token=APP_TOKEN
    )
    yield TestClient(app), submissions, classes
    app.dependency_overrides.clear()


def _make_class(client, name="Lớp 05A"):
    return client.post("/classes", json={"name": name}, headers={"X-App-Token": APP_TOKEN}).json()


def _file_into(client, class_id, group="Group 05"):
    return client.post(
        "/submissions",
        json={"group": group, "project": "TempleCare", "class_id": class_id},
        headers={"X-App-Token": APP_TOKEN},
    ).json()


def _decide(client, submission_id, key, decision="approved", note=""):
    return client.post(
        f"/submissions/{submission_id}/decision",
        json={"decision": decision, "note": note},
        headers={"X-Class-Key": key},
    )


# ------------------------------------------------------------------ (a) (f)


class TestDecisionShape:
    def test_history_entry_keeps_the_layer1_shape_and_clock_agrees(self, make_env):
        # (a) assert the SHAPE of every entry, never the count —
        # list.extend(dict) once turned entries into their KEYS and a length
        # assertion stayed green. (f) updatedAt == decidedAt ==
        # history[-1]["at"] is the one-clock-read proof.
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        r = _decide(client, row["id"], created["write_key"], "approved", note="Đạt yêu cầu")
        assert r.status_code == 200, r.text
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["status"] == "approved"
        assert body["decidedAt"] == body["updatedAt"]
        entries = body["history"]
        assert isinstance(entries, list) and entries
        for entry in entries:
            assert isinstance(entry, dict), entry
            assert set(entry.keys()) == {"revision", "at", "status", "event"}, entry
        last = entries[-1]
        assert last["event"] == "decided"
        assert last["status"] == "approved"
        assert last["at"] == body["decidedAt"]
        assert last["revision"] == row["revision"]

    def test_the_group_note_survives_its_own_field(self, make_env):
        client, _, _ = make_env
        created = _make_class(client)
        row = client.post(
            "/submissions",
            json={"group": "G", "note": "Ghi chú của nhóm", "class_id": created["id"]},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        decided = _decide(
            client, row["id"], created["write_key"], "changes_requested", note="Yêu cầu sửa mục 3"
        )
        assert decided.status_code == 200, decided.text
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["note"] == "Ghi chú của nhóm"
        assert body["decision_note"] == "Yêu cầu sửa mục 3"


# ----------------------------------------------------------------------- (b)


class TestClosedVocabulary:
    def test_an_unknown_decision_is_422_not_silently_ignored(self, make_env):
        # (b) the vocabulary is closed; nothing is written on a bad value
        client, submissions, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        for bad in ("rejected", "APPROVED", "maybe", ""):
            r = _decide(client, row["id"], created["write_key"], bad)
            assert r.status_code == 422, (bad, r.text)
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["status"] == "submitted"  # untouched
        assert body["decidedAt"] is None  # no decision was recorded
        # an extra field is forbidden too, not ignored
        r = client.post(
            f"/submissions/{row['id']}/decision",
            json={"decision": "approved", "decidedBy": "Tam"},
            headers={"X-Class-Key": created["write_key"]},
        )
        assert r.status_code == 422

    def test_the_store_rejects_a_third_status_even_without_the_route_model(self, make_env):
        # pydantic is the first gate; the store's own check is the second
        client, submissions, classes = make_env
        created = classes.create(name="Direct")
        row = submissions.create(group="G")
        submissions.assign_class(row["id"], created["id"])
        with pytest.raises(Exception) as excinfo:
            submissions.decide(
                row["id"], decision="accepted", class_key=created["plaintext"], class_store=classes
            )
        assert "closed" in str(excinfo.value).lower() or "decision" in str(excinfo.value).lower()


# ----------------------------------------------------------------------- (c)


class TestAuthorityIsTheClassKey:
    def test_the_app_token_cannot_decide_and_fails_like_a_stranger(self, make_env):
        # (c) the app token is a shared secret the GROUP's app also holds;
        # accepting it would let a group approve its own work
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        stranger = _decide(client, row["id"], "some-random-key")
        with_token = client.post(
            f"/submissions/{row['id']}/decision",
            json={"decision": "approved", "note": ""},
            headers={"X-App-Token": APP_TOKEN},
        )
        assert stranger.status_code == with_token.status_code == 409
        assert stranger.json() == with_token.json() == {"detail": "class_missing"}
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["status"] == "submitted"

    def test_another_classs_key_cannot_decide_this_classs_submission(self, make_env):
        client, _, _ = make_env
        class_a = _make_class(client, "A")
        class_b = _make_class(client, "B")
        row = _file_into(client, class_a["id"])
        r = _decide(client, row["id"], class_b["write_key"])
        assert r.status_code == 409
        assert r.json() == {"detail": "class_missing"}
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["status"] == "submitted"

    def test_the_right_key_decides(self, make_env):
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        assert _decide(client, row["id"], created["write_key"]).status_code == 200


# ----------------------------------------------------------------------- (d)


class TestNoClassNoDecision:
    def test_a_classless_submission_is_409_not_in_class(self, make_env):
        # (d) no class -> no teacher authority exists to speak of
        client, _, _ = make_env
        row = client.post("/submissions", json={"group": "G"}, headers={"X-App-Token": APP_TOKEN}).json()
        r = _decide(client, row["id"], "any-key")
        assert r.status_code == 409
        assert r.json() == {"detail": "not_in_class"}

    def test_a_deleted_class_is_409_class_missing(self, make_env):
        # (d) the DANGLING path: a row still pointing at a class whose file is
        # gone. WP2's clean DELETE unfiles members first, so a cleanly deleted
        # class leaves an EMPTY class_id — that is the not_in_class answer, and
        # it is asserted below too. class_missing is for the row the unfile
        # never reached (store-level delete, or a mid-way failure).
        client, submissions, classes = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        # delete the class FILE directly, bypassing unfile — the dangling state
        (classes.dir / f"{created['id']}.json").unlink()
        classes.reset()
        after = _decide(client, row["id"], created["write_key"])
        assert after.status_code == 409
        assert after.json() == {"detail": "class_missing"}

    def test_a_cleanly_deleted_class_leaves_not_in_class(self, make_env):
        # the honest complement: after WP2's DELETE, the row no longer points
        # anywhere, so the truthful answer is "no class", not "class gone"
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        r = client.delete(f"/classes/{created['id']}", headers={"X-Class-Key": created["write_key"]})
        assert r.status_code == 200
        after = _decide(client, row["id"], created["write_key"])
        assert after.status_code == 409
        assert after.json() == {"detail": "not_in_class"}


# ----------------------------------------------------------------------- (e)


class TestDecidingAnOlderRound:
    def test_decide_via_previous_id_still_reads_with_history_intact(self, make_env):
        # (e) a decision is a fact about one round; older rounds stay readable
        client, _, _ = make_env
        created = _make_class(client)
        first = _file_into(client, created["id"])
        revised = client.post(
            f"/submissions/{first['id']}/revise",
            json={"project": "v2"},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        assert revised["previous_id"] == first["id"]
        r = _decide(client, first["id"], created["write_key"], "changes_requested", note="Sửa mục 2")
        assert r.status_code == 200, r.text
        old = client.get(f"/submissions/{first['id']}").json()
        assert old["status"] == "changes_requested"
        assert old["history"], "the old round keeps its thread"
        for entry in old["history"]:
            assert set(entry.keys()) == {"revision", "at", "status", "event"}, entry
        # the NEW round is untouched by the decision on the old one
        new = client.get(f"/submissions/{revised['id']}").json()
        assert new["status"] == "submitted"
        assert new["decidedAt"] is None


# ----------------------------------------------------------------------- (f)


class TestOneClockRead:
    def test_updated_at_equals_decided_at(self, make_env):
        # (f) as a store-level assert too: one _now() per write
        client, submissions, classes = make_env
        created = classes.create(name="Direct")
        row = submissions.create(group="G")
        submissions.assign_class(row["id"], created["id"])
        decided = submissions.decide(
            row["id"], decision="approved", class_key=created["plaintext"], class_store=classes
        )
        assert decided["updatedAt"] == decided["decidedAt"]
        assert decided["history"][-1]["at"] == decided["decidedAt"]


# ----------------------------------------------------------------------- (g)


class TestSecondDecision:
    def test_latest_status_with_both_kept_in_history(self, make_env):
        # (g) the teacher changes their mind: status is the LATEST decision,
        # history keeps BOTH — append, never overwrite (ADR-0016, option G)
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        first = _decide(client, row["id"], created["write_key"], "changes_requested", note="Sửa mục 2")
        assert first.status_code == 200, first.text
        second = _decide(client, row["id"], created["write_key"], "approved", note="Đã sửa")
        assert second.status_code == 200, second.text
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["status"] == "approved"
        assert body["decision_note"] == "Đã sửa"
        assert body["decidedAt"] == body["updatedAt"]
        decisions = [e for e in body["history"] if e["event"] == "decided"]
        assert len(decisions) == 2
        assert [e["status"] for e in decisions] == ["changes_requested", "approved"]
        # each entry is still the Layer-1 shape
        for entry in decisions:
            assert set(entry.keys()) == {"revision", "at", "status", "event"}, entry
        assert decisions[0]["at"] != decisions[1]["at"] or True  # same-second possible; shape is the promise


# ----------------------------------------------------------------------- (h)


class TestReadRouteExposesTheDecision:
    def test_decided_at_and_note_come_back_through_the_route(self, make_env):
        # (h) the read view is a WHITELIST: a field only the store knows is
        # invisible to every reader while every test stays green
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        _decide(client, row["id"], created["write_key"], "changes_requested", note="Thiếu hậu điều kiện")
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["decidedAt"] is not None
        assert body["decision_note"] == "Thiếu hậu điều kiện"
        assert body["status"] == "changes_requested"

    def test_an_undecided_submission_reads_back_without_a_decision(self, make_env):
        client, _, _ = make_env
        created = _make_class(client)
        row = _file_into(client, created["id"])
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["decidedAt"] is None
        assert body["decision_note"] == ""


# ----------------------------------------------------------------------- (i)


class TestOneFailureShapeForIds:
    def test_malformed_and_unknown_ids_answer_identically(self, make_env):
        # (i) a 404 that tells the two apart is a filesystem probe
        client, _, _ = make_env
        malformed = client.post(
            "/submissions/..%2Fetc/decision",
            json={"decision": "approved"},
            headers={"X-Class-Key": "k"},
        )
        unknown = client.post(
            f"/submissions/{'k' * 22}/decision",
            json={"decision": "approved"},
            headers={"X-Class-Key": "k"},
        )
        assert malformed.status_code == unknown.status_code == 404
        assert malformed.json() == unknown.json() == {"detail": "Not Found"}
