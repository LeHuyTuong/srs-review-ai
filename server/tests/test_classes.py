"""Class CRUD — plan 12 WP2, ADR-0017 (docs/adr/0017-class-crud-and-write-key.md).

Every test maps to an acceptance criterion (a)–(j) in plan 12 §2 WP2; the
mapping is in the test's first-line comment. Negative tests are first-class:
a route that stays green because a list happens to be empty proves nothing.
"""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.classes import ClassStore
from app.infrastructure.submissions import SubmissionStore
from app.main import app

APP_TOKEN = "test-app-secret"


@pytest.fixture()
def make_env(tmp_path, monkeypatch):
    """One app + one class store over throwaway dirs; the route layer joins them."""
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


def _create_class(client, name="Lớp 05A"):
    return client.post("/classes", json={"name": name}, headers={"X-App-Token": APP_TOKEN})


def _file_via_post(client, class_id, group="Group 05", **extra):
    """The group's path: POST /submissions with a class_id."""
    return client.post(
        "/submissions",
        json={"group": group, "project": "TempleCare", "class_id": class_id, **extra},
        headers={"X-App-Token": APP_TOKEN},
    )


def _file_direct(store: SubmissionStore, class_id, group="Group 05"):
    """The store-level path used to stage rows for class-route tests."""
    row = store.create(group=group, project="TempleCare")
    if class_id:
        store.assign_class(row["id"], class_id)
    return row


# ------------------------------------------------------------------------ (a)


class TestOneFailureShape:
    def test_malformed_and_unknown_class_ids_answer_identically(self, make_env):
        # (a) a 404 that tells the two apart is a filesystem probe
        client, _, _ = make_env
        malformed = client.get("/classes/..%2Fetc")
        unknown = client.get(f"/classes/{'k' * 22}")
        assert malformed.status_code == unknown.status_code == 404
        assert malformed.json() == unknown.json()
        # same on the write path: rename with the app token AND a bad id
        bad_patch = client.patch(
            f"/classes/{'k' * 22}", json={"name": "X"}, headers={"X-Class-Key": "whatever"}
        )
        assert bad_patch.status_code == 404
        assert bad_patch.json() == unknown.json()

    def test_path_traversal_ids_stay_plain_404s(self, make_env):
        # (i) a malformed class_id must not read outside the store directory
        client, _, classes = make_env
        secret = classes.dir.parent / "secret.json"
        secret.write_text(json.dumps({"pwn": True}), encoding="utf-8")
        try:
            for probe in ("..", "../secret", "%2e%2e%2fsecret", "..\\secret"):
                r = client.get(f"/classes/{probe}")
                assert r.status_code == 404, probe
                assert r.json() == {"detail": "Not Found"}
        finally:
            secret.unlink(missing_ok=True)


# ------------------------------------------------------------------------ (b)


class TestWritePathIsNoOracle:
    def test_holder_of_key_a_gets_b_in_a_strangers_shape(self, make_env):
        # (b) holding A's key must not reveal anything about B — not even that
        # B exists. Same 404 body as a stranger with a random key.
        client, _, _ = make_env
        key_a = _create_class(client, "A").json()["write_key"]
        _create_class(client, "B")
        stranger = client.patch(
            f"/classes/{'z' * 22}", json={"name": "X"}, headers={"X-Class-Key": "random-guess"}
        )
        holder = client.patch(f"/classes/{'z' * 22}", json={"name": "X"}, headers={"X-Class-Key": key_a})
        assert stranger.status_code == holder.status_code == 404
        assert stranger.json() == holder.json()

    def test_wrong_key_on_rename_is_the_same_404_as_unknown(self, make_env):
        client, _, _ = make_env
        created = _create_class(client).json()
        wrong = client.patch(
            f"/classes/{created['id']}", json={"name": "New"}, headers={"X-Class-Key": "wrong-key"}
        )
        assert wrong.status_code == 404
        assert wrong.json() == {"detail": "Not Found"}

    def test_presence_of_any_header_is_not_authority(self, make_env):
        client, submissions, _ = make_env
        created = _create_class(client).json()
        row = _file_direct(submissions, created["id"])
        # junk key on the filing verbs: 404, never success
        assert (
            client.post(
                f"/classes/{created['id']}/submissions",
                json={"submission_id": row["id"]},
                headers={"X-Class-Key": "junk"},
            ).status_code
            == 404
        )
        assert (
            client.delete(
                f"/classes/{created['id']}/submissions/{row['id']}",
                headers={"X-Class-Key": "junk"},
            ).status_code
            == 404
        )

    def test_the_app_token_is_not_a_class_key(self, make_env):
        # ADR-0017 decision 1: the app token is a shared secret; accepting it
        # for class writes would let every install delete any teacher's class.
        client, _, _ = make_env
        created = _create_class(client).json()
        r = client.patch(
            f"/classes/{created['id']}",
            json={"name": "Renamed by the app token"},
            headers={"X-App-Token": APP_TOKEN},
        )
        assert r.status_code in (401, 403, 404)


# ------------------------------------------------------------------------ (c)


class TestWriteKeyVisibleExactlyOnce:
    def test_create_response_carries_the_key_a_reread_does_not(self, make_env):
        # (c) the create response is the only delivery of the plaintext key
        client, _, _ = make_env
        created = _create_class(client).json()
        assert created["write_key"]
        reread = client.get(f"/classes/{created['id']}").json()
        assert "write_key" not in reread
        # the disk copy holds the hash only
        on_disk = json.loads((_store_dir(make_env) / f"{created['id']}.json").read_text(encoding="utf-8"))
        assert "write_key" not in on_disk
        assert len(on_disk["write_key_hash"]) == 64

    def test_the_key_actually_works(self, make_env):
        client, _, _ = make_env
        created = _create_class(client).json()
        r = client.patch(
            f"/classes/{created['id']}",
            json={"name": "Đổi tên được"},
            headers={"X-Class-Key": created["write_key"]},
        )
        assert r.status_code == 200, r.text
        assert r.json()["name"] == "Đổi tên được"


def _store_dir(make_env):
    client, _, classes = make_env
    return classes.dir


# ------------------------------------------------------------------------ (d)


class TestPatchRenamesAndOnlyRenames:
    def test_rename_keeps_the_id(self, make_env):
        client, _, _ = make_env
        created = _create_class(client).json()
        before = created["id"]
        r = client.patch(
            f"/classes/{before}", json={"name": "Tên mới"}, headers={"X-Class-Key": created["write_key"]}
        )
        assert r.status_code == 200
        assert r.json()["id"] == before
        assert client.get(f"/classes/{before}").json()["name"] == "Tên mới"

    def test_patch_carrying_an_id_change_is_422_not_silent(self, make_env):
        # (d) extra="forbid" must turn an id change into a rejection
        client, _, _ = make_env
        created = _create_class(client).json()
        r = client.patch(
            f"/classes/{created['id']}",
            json={"name": "X", "class_id": "attacker-chosen-id"},
            headers={"X-Class-Key": created["write_key"]},
        )
        assert r.status_code == 422, r.text

    def test_patch_carrying_the_hash_field_is_422_too(self, make_env):
        client, _, _ = make_env
        created = _create_class(client).json()
        r = client.patch(
            f"/classes/{created['id']}",
            json={"name": "X", "write_key_hash": "0" * 64},
            headers={"X-Class-Key": created["write_key"]},
        )
        assert r.status_code == 422


# ------------------------------------------------------------------------ (e)


class TestDeleteUnfilesNeverDeletesWork:
    def test_after_delete_submissions_survive_unlinked(self, make_env):
        # (e) the delete button is aimed at other people's work
        client, submissions, _ = make_env
        created = _create_class(client).json()
        rows = [_file_direct(submissions, created["id"], group=f"G{i}") for i in range(2)]
        listed = client.get(f"/classes/{created['id']}").json()
        assert len(listed["submissions"]) == 2
        r = client.delete(f"/classes/{created['id']}", headers={"X-Class-Key": created["write_key"]})
        assert r.status_code == 200, r.text
        assert r.json()["dangling"] == []
        assert r.json()["unfiled"] == 2
        # class is gone, same 404 shape
        assert client.get(f"/classes/{created['id']}").json() == {"detail": "Not Found"}
        # every submission is still readable by its own id, class_id now empty
        for row in rows:
            read = client.get(f"/submissions/{row['id']}")
            assert read.status_code == 200
            assert read.json()["class_id"] == ""
        # and it appears in no class listing — there are none left
        assert (
            not (submissions.dir / f"{rows[0]['id']}.json")
            .read_text(encoding="utf-8")
            .count(f'"class_id": "{created["id"]}"')
        )


# ------------------------------------------------------------------------ (f)


class TestListingOrderIsTimeNotRounds:
    def test_members_are_sorted_by_created_at_desc(self, make_env):
        # (f) revision is the number of rounds, not a time; the queue is time.
        # Rows created within the same second share createdAt, so the test
        # stamps DISTINCT times instead of racing the clock (two rows written
        # in one second are equal, and their order is then arbitrary).
        client, submissions, _ = make_env
        created = _create_class(client).json()
        first = _file_direct(submissions, created["id"], group="First")
        second = _file_direct(submissions, created["id"], group="Second")
        older = _file_direct(submissions, created["id"], group="Oldest")
        stamps = {
            first["id"]: "2026-09-27T10:00:00Z",
            second["id"]: "2026-09-27T10:00:01Z",
            older["id"]: "2026-01-01T00:00:00Z",
        }
        for sid, stamp in stamps.items():
            path = submissions.dir / f"{sid}.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["createdAt"] = stamp
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        submissions.reset()
        listed = client.get(f"/classes/{created['id']}").json()["submissions"]
        ids = [row["id"] for row in listed]
        assert ids == [second["id"], first["id"], older["id"]], ids

    def test_every_member_row_has_a_created_at(self, make_env):
        client, submissions, _ = make_env
        created = _create_class(client).json()
        _file_direct(submissions, created["id"])
        _file_direct(submissions, created["id"])
        listed = client.get(f"/classes/{created['id']}").json()["submissions"]
        assert listed, "the listing must not be empty — an empty pass proves nothing"
        assert all(row["createdAt"] for row in listed)


# ------------------------------------------------------------------------ (g)


class TestUnknownClassOnSubmission:
    def test_post_submissions_with_unknown_class_is_422_naming_the_field(self, make_env):
        # (g) a silent drop would file work into a void the teacher never sees
        client, _, _ = make_env
        r = _file_via_post(client, "k" * 22)
        assert r.status_code == 422, r.text
        assert "class_id" in r.text

    def test_post_submissions_with_a_real_class_files_it(self, make_env):
        client, _, _ = make_env
        created = _create_class(client).json()
        r = _file_via_post(client, created["id"])
        assert r.status_code == 201, r.text
        listed = client.get(f"/classes/{created['id']}").json()["submissions"]
        assert [row["id"] for row in listed] == [r.json()["id"]]

    def test_a_submission_is_in_at_most_one_class(self, make_env):
        # ADR-0017 option E: one source of truth makes two classes unrepresentable
        client, submissions, _ = make_env
        class_a = _create_class(client, "A").json()
        class_b = _create_class(client, "B").json()
        _file_direct(submissions, class_a["id"])
        row = submissions.all_rows()
        the_row = next(iter(row.values()))
        the_row_id = the_row["id"]
        submissions.assign_class(the_row_id, class_b["id"])
        assert client.get(f"/classes/{class_a['id']}").json()["submissions"] == []
        assert [r["id"] for r in client.get(f"/classes/{class_b['id']}").json()["submissions"]] == [
            the_row_id
        ]


# ------------------------------------------------------------------------ (h)


class TestReadRouteExposesTheClass:
    def test_read_submission_shows_class_id_through_the_route(self, make_env):
        # (h) the read route is a WHITELIST — a field only the store knows is
        # invisible to every reader while every test stays green
        client, submissions, _ = make_env
        created = _create_class(client).json()
        row = _file_direct(submissions, created["id"])
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["class_id"] == created["id"]

    def test_unfiled_submission_reads_back_with_empty_class_id(self, make_env):
        client, submissions, _ = make_env
        created = _create_class(client).json()
        row = _file_direct(submissions, created["id"])
        submissions.unassign_class(row["id"])
        body = client.get(f"/submissions/{row['id']}").json()
        assert body["class_id"] == ""


# --------------------------------------------------------------------- (j)


class TestDeleteIsWriteManyAndDeliberate:
    def test_a_broken_member_file_does_not_stop_the_delete(self, make_env):
        # (j) delete is write-many over members; a failure halfway must leave
        # the rest readable and still remove the class — VISIBLE, not silent
        client, submissions, _ = make_env
        created = _create_class(client).json()
        good = _file_direct(submissions, created["id"], group="Good")
        broken = _file_direct(submissions, created["id"], group="Broken")
        (submissions.dir / f"{broken['id']}.json").write_text("{not json", encoding="utf-8")
        submissions.reset()
        r = client.delete(f"/classes/{created['id']}", headers={"X-Class-Key": created["write_key"]})
        assert r.status_code == 200, r.text
        # the broken file never entered the index (P2's design: damaged rows
        # are skipped), so it is neither unfiled nor dangling — it is a row
        # the store never saw. The count is what makes that visible.
        assert r.json() == {"deleted": created["id"], "unfiled": 1, "dangling": []}
        # the healthy submission survives, unlinked, still readable
        body = client.get(f"/submissions/{good['id']}").json()
        assert body["class_id"] == ""
        assert body["group"] == "Good"
        # the class row is gone
        assert client.get(f"/classes/{created['id']}").status_code == 404

    def test_unfile_failure_is_reported_not_swallowed(self, make_env):
        # the same AC from the store's side: the caller learns which rows dangle
        client, submissions, classes = make_env
        created = classes.create(name="Direct")
        row = _file_direct(submissions, created["id"])
        original = submissions.unassign_class

        def explode(submission_id):
            raise RuntimeError("disk full")

        submissions.unassign_class = explode  # type: ignore[method-assign]
        dangling = classes.delete(
            created["id"],
            write_key=created["plaintext"],
            submission_index=submissions.all_rows(),
            unfile=submissions.unassign_class,
        )
        submissions.unassign_class = original  # type: ignore[method-assign]
        assert dangling == {"unfiled": 0, "dangling": [row["id"]]}


# ------------------------------------------------------- cross-store plumbing


class TestRoundTripThroughBothStores:
    def test_revisions_stay_in_their_class(self, make_env):
        # next_revision carries class_id forward — otherwise round two drops
        # out of every class listing (membership lives on the row)
        client, submissions, _ = make_env
        created = _create_class(client).json()
        filed = _file_via_post(client, created["id"]).json()
        revised = client.post(
            f"/submissions/{filed['id']}/revise",
            json={"project": "TempleCare v2"},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        listed = client.get(f"/classes/{created['id']}").json()["submissions"]
        ids = {row["id"] for row in listed}
        assert filed["id"] in ids
        assert revised["id"] in ids

    def test_class_survives_a_server_restart(self, make_env):
        # one file per class on disk — a fresh store instance must see it
        client, submissions, classes = make_env
        created = _create_class(client).json()
        _file_direct(submissions, created["id"])
        classes.reset()
        revived = ClassStore(class_dir=classes.dir)
        assert revived.exists(created["id"])
        members = revived.list_members(created["id"], submissions.all_rows())
        assert len(members) == 1

    def test_damaged_class_file_is_skipped_not_fatal(self, make_env):
        # the store's own resilience promise: one unreadable file must not
        # take the whole store down
        client, _, classes = make_env
        good = _create_class(client, "Good").json()
        (classes.dir / "broken.json").write_text("{oops", encoding="utf-8")
        classes.reset()
        assert classes.exists(good["id"])
        assert not classes.exists("broken")

    def test_no_auth_on_the_read_route(self, make_env):
        # the id IS the credential, as /submissions/{id}
        client, submissions, _ = make_env
        created = _create_class(client).json()
        _file_direct(submissions, created["id"])
        r = client.get(f"/classes/{created['id']}")
        assert r.status_code == 200
        assert r.json()["name"] == "Lớp 05A"
