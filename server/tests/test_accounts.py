"""The account and session store — ADR-0020, over a real SQLite file.

Each test here is one of the four claims ADR-0020 makes, and the two that
matter most are the two a permissive fake would hide:

* **A stored session is not a usable session.** The token is hashed, so the
  test reads the DATABASE FILE and asserts the raw token is absent — a
  `count_sessions()` assertion would pass while every token sat in the clear.
* **Revocation is real.** Deleting a session row makes the very next resolve
  fail. This is the property ADR-0016 traded away and ADR-0020 bought back, so
  it is asserted directly rather than inferred from the delete's return value.

The login-oracle test is the third: wrong password and unknown username must be
indistinguishable, including in what they raise.
"""

from __future__ import annotations

import base64
import hashlib
import sqlite3
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from app.infrastructure.accounts import (
    PASSWORD_MIN,
    ROLES,
    SESSION_TTL,
    AccountStore,
    InvalidAccountInputError,
    InvalidCredentialsError,
    UsernameTakenError,
    hash_password,
    hash_token,
    verify_password,
)


@pytest.fixture
def store(tmp_path: Path) -> AccountStore:
    s = AccountStore(tmp_path / "accounts.sqlite3")
    yield s
    s.close()


def _teacher(store: AccountStore, username: str = "teacher1") -> dict:
    return store.register(username, "matkhau-du-dai", "teacher")


# ---------------------------------------------------------------- hashing


class TestPasswordHashing:
    def test_a_hash_does_not_contain_the_password(self) -> None:
        h = hash_password("correct horse battery staple")
        assert "correct" not in h
        assert h.startswith("scrypt$")

    def test_the_same_password_hashes_differently_each_time(self) -> None:
        # A per-row salt. Identical hashes for identical passwords would let one
        # leaked row identify every account sharing that password.
        a = hash_password("same-password")
        b = hash_password("same-password")
        assert a != b

    def test_parameters_ride_with_the_hash(self) -> None:
        # The n/r/p are IN the stored string, so raising the work factor later
        # does not invalidate existing rows.
        scheme, n, r, p, salt_b64, hash_b64 = hash_password("x" * 12).split("$")
        assert scheme == "scrypt"
        assert (int(n), int(r), int(p)) == (2**14, 8, 1)
        assert len(base64.b64decode(salt_b64)) == 16
        assert len(base64.b64decode(hash_b64)) == 64

    @pytest.mark.parametrize(
        "stored",
        [
            "",
            "not-a-hash",
            "bcrypt$12$whatever",
            "scrypt$16384$8$1$%%%$%%%",
            "scrypt$nope$8$1$AAAA$AAAA",
            "scrypt$16384$8",  # truncated
        ],
    )
    def test_a_malformed_row_is_a_failed_login_not_a_crash(self, stored: str) -> None:
        # A row this build cannot parse must not raise out of a login route:
        # that is an account nobody can use and nobody can diagnose.
        assert verify_password("anything", stored) is False

    def test_verify_accepts_the_right_password_and_rejects_the_rest(self) -> None:
        h = hash_password("dung-mat-khau")
        assert verify_password("dung-mat-khau", h) is True
        assert verify_password("dung-mat-kha", h) is False
        assert verify_password("dung-mat-khau ", h) is False


# ---------------------------------------------------------------- register


class TestRegister:
    def test_registers_and_returns_no_password_material(self, store: AccountStore) -> None:
        user = _teacher(store)
        assert user["role"] == "teacher"
        assert user["username"] == "teacher1"
        # The hash must not be in the returned dict at all — a caller that never
        # receives it cannot log it.
        assert "password_hash" not in user
        assert "password" not in user
        # The exact key set, pinned: adding a field to this row is a change a
        # reader should have to acknowledge, not discover.
        assert list(user) == ["id", "username", "role", "createdAt", "classId", "group"]

    def test_membership_is_stored_and_read_back(self, store: AccountStore) -> None:
        """`class_id` / `grp` are what make a filtered list possible (ADR-0020 §4)."""
        teacher = store.register("gv01", "matkhau-du-dai", "teacher", class_id="  cls-abc  ")
        assert teacher["classId"] == "cls-abc", "the class id should be stripped, not kept raw"
        assert teacher["group"] is None

        student = store.register("sv01", "matkhau-du-dai", "student", group="Nhom 4")
        assert student["group"] == "Nhom 4"
        assert student["classId"] is None

        # Unauthenticated reads must carry it too, or the list route cannot see
        # who it is filtering for.
        assert store.get_user(teacher["id"])["classId"] == "cls-abc"
        assert store.find_by_username("sv01")["group"] == "Nhom 4"
        assert store.authenticate("gv01", "matkhau-du-dai")["classId"] == "cls-abc"

    def test_an_account_with_no_membership_gets_nulls_not_an_error(self, store: AccountStore) -> None:
        # The common case: somebody registers before a class exists. The list
        # route must render an EMPTY list for them, not raise.
        user = store.register("gv02", "matkhau-du-dai", "teacher")
        assert user["classId"] is None and user["group"] is None

    def test_set_membership_attaches_and_reports_a_missing_user(self, store: AccountStore) -> None:
        user = store.register("gv03", "matkhau-du-dai", "teacher")
        updated = store.set_membership(user["id"], class_id="cls-xyz")
        assert updated is not None and updated["classId"] == "cls-xyz"
        # Assigning a group replaces the pair, and assigning nothing clears both.
        assert store.set_membership(user["id"], group="Nhom 9")["group"] == "Nhom 9"
        assert store.set_membership(user["id"])["classId"] is None
        # No such user is None, not an exception — a route maps this to 404.
        assert store.set_membership("khong-ton-tai", class_id="cls-1") is None

    def test_a_pre_existing_database_gains_the_new_columns(self, tmp_path: Path) -> None:
        """The migration, exercised against a table built WITHOUT the columns.

        `CREATE TABLE IF NOT EXISTS` silently does nothing to an existing table,
        so a database written by the previous build would keep its old shape and
        every read of `class_id` would raise `no such column`. This builds that
        old shape by hand and asserts the store repairs it on open.
        """
        path = tmp_path / "old.sqlite3"
        with sqlite3.connect(path) as conn:
            conn.execute(
                "CREATE TABLE users ("
                "  id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE,"
                "  password_hash TEXT NOT NULL, role TEXT NOT NULL,"
                "  created_at TEXT NOT NULL)"
            )
            conn.execute(
                "CREATE TABLE sessions ("
                "  token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,"
                "  created_at TEXT NOT NULL, expires_at TEXT NOT NULL)"
            )
            conn.execute(
                "INSERT INTO users VALUES "
                "('u1','olduser','scrypt$16384$8$1$AAAA$AAAA','teacher','2026-01-01')"
            )
            conn.commit()

        store = AccountStore(path)
        # The old row is readable and reports no membership rather than raising.
        found = store.find_by_username("olduser")
        assert found is not None and found["classId"] is None
        # And a fresh registration can set the new columns.
        created = store.register("gv-new", "matkhau-du-dai", "teacher", class_id="cls-new")
        assert store.get_user(created["id"])["classId"] == "cls-new"
        store.close()

    def test_opening_twice_does_not_try_to_re_add_the_columns(self, tmp_path: Path) -> None:
        # A blind `ALTER TABLE` raises "duplicate column name" the second time,
        # which would make the store unusable after one restart.
        path = tmp_path / "twice.sqlite3"
        first = AccountStore(path)
        first.register("gv01", "matkhau-du-dai", "teacher", class_id="cls-1")
        first.close()
        second = AccountStore(path)
        assert second.find_by_username("gv01")["classId"] == "cls-1"
        second.close()

    def test_a_duplicate_username_is_refused(self, store: AccountStore) -> None:
        _teacher(store)
        with pytest.raises(UsernameTakenError):
            _teacher(store)

    def test_username_is_stripped_before_the_uniqueness_check(self, store: AccountStore) -> None:
        _teacher(store, "teacher1")
        with pytest.raises(UsernameTakenError):
            # Trailing space must not create a second account a human would
            # read as the same name.
            _teacher(store, "teacher1 ")

    @pytest.mark.parametrize("bad", ["ab", "", "a" * 65, "has space", "hỏi?anh", "semi;colon"])
    def test_a_bad_username_shape_is_refused(self, store: AccountStore, bad: str) -> None:
        with pytest.raises(InvalidAccountInputError):
            store.register(bad, "matkhau-du-dai", "teacher")

    def test_a_short_password_is_refused(self, store: AccountStore) -> None:
        with pytest.raises(InvalidAccountInputError):
            store.register("teacher2", "x" * (PASSWORD_MIN - 1), "teacher")
        # And exactly at the boundary it is accepted.
        assert store.register("teacher3", "x" * PASSWORD_MIN, "teacher")["id"]

    def test_an_unknown_role_is_refused(self, store: AccountStore) -> None:
        with pytest.raises(InvalidAccountInputError):
            store.register("teacher4", "matkhau-du-dai", "admin")
        assert ROLES == ("teacher", "student")

    def test_the_password_is_not_stored_in_the_clear(self, store: AccountStore) -> None:
        _teacher(store)
        raw = store.path.read_text(errors="ignore")
        assert "matkhau-du-dai" not in raw


# ---------------------------------------------------------------- authenticate


class TestAuthenticate:
    def test_valid_credentials_return_the_user(self, store: AccountStore) -> None:
        created = _teacher(store)
        found = store.authenticate("teacher1", "matkhau-du-dai")
        assert found["id"] == created["id"]
        assert found["role"] == "teacher"
        assert "password_hash" not in found

    def test_wrong_password_and_unknown_username_are_indistinguishable(self, store: AccountStore) -> None:
        """The enumeration oracle this design exists to close.

        Two DIFFERENT facts — "that user exists but the password is wrong" and
        "no such user" — must produce the same exception type and the same
        message. A route maps both to one 401; if the type differed here, the
        route would leak by accident.
        """
        _teacher(store)
        with pytest.raises(InvalidCredentialsError) as wrong_password:
            store.authenticate("teacher1", "sai-mat-khau")
        with pytest.raises(InvalidCredentialsError) as no_such_user:
            store.authenticate("khong-ton-tai", "sai-mat-khau")
        assert str(wrong_password.value) == str(no_such_user.value)
        assert type(wrong_password.value) is type(no_such_user.value)

    def test_username_is_stripped_on_login_too(self, store: AccountStore) -> None:
        _teacher(store)
        assert store.authenticate("  teacher1  ", "matkhau-du-dai")["username"] == "teacher1"

    def test_a_missing_user_still_pays_the_hash_cost(self, store: AccountStore) -> None:
        """The timing half of the same oracle.

        Returning early on "no such user" makes a missing account measurably
        faster than a wrong password. The dummy verify keeps the two in the same
        band; the assertion is loose (a factor of 8) because CI machines are
        noisy, but it fails loudly if the dummy verify is ever removed.
        """
        _teacher(store)
        t0 = time.perf_counter()
        with pytest.raises(InvalidCredentialsError):
            store.authenticate("teacher1", "sai")
        known_cost = time.perf_counter() - t0

        t0 = time.perf_counter()
        with pytest.raises(InvalidCredentialsError):
            store.authenticate("khong-ton-tai", "sai")
        unknown_cost = time.perf_counter() - t0

        assert unknown_cost > known_cost / 8, (
            f"unknown user took {unknown_cost * 1000:.2f} ms against "
            f"{known_cost * 1000:.2f} ms for a known one — the dummy verify is "
            "missing and the login route is a username oracle"
        )


# ---------------------------------------------------------------- sessions


class TestSessions:
    def test_the_raw_token_never_reaches_the_database(self, store: AccountStore) -> None:
        """The claim a `count_sessions()` assertion would not test.

        Reads the FILE. A copy of this database must not be a set of live
        sessions, exactly as a copy of the class store is not a set of write
        keys (ADR-0017).
        """
        user = _teacher(store)
        token, _ = store.start_session(user["id"])
        # Read BOTH the main file and the WAL sidecar. The store runs in WAL
        # mode (PRAGMA journal_mode=WAL in `_open`), so a freshly committed row
        # lives in `accounts.sqlite3-wal` until a checkpoint — reading only the
        # main file produced a FALSE PASS on the "is the token hashed" question
        # for the wrong reason (nothing was there to find).
        raw = store.path.read_bytes()
        sidecar = Path(f"{store.path}-wal")
        if sidecar.exists():
            raw += sidecar.read_bytes()
        assert token.encode() not in raw, "the session token is stored in the clear"
        # And what IS stored is the hash.
        assert hash_token(token).encode() in raw

    def test_a_live_token_resolves_to_its_user(self, store: AccountStore) -> None:
        user = _teacher(store)
        token, _ = store.start_session(user["id"])
        resolved = store.resolve_session(token)
        assert resolved is not None
        assert resolved["id"] == user["id"]
        assert resolved["role"] == "teacher"

    def test_an_unknown_token_resolves_to_nothing(self, store: AccountStore) -> None:
        assert store.resolve_session("khong-phai-token") is None
        assert store.resolve_session("") is None

    def test_revoking_a_session_kills_it_immediately(self, store: AccountStore) -> None:
        """ADR-0020's whole purchase over ADR-0016.

        ADR-0016 §Consequences: "no revocation once a link leaks". A session row
        buys that back, so the test asserts the NEXT resolve fails — not the
        delete's return value, which would pass even if lookups ignored the
        table.
        """
        user = _teacher(store)
        token, _ = store.start_session(user["id"])
        assert store.resolve_session(token) is not None

        assert store.end_session(token) is True
        assert store.resolve_session(token) is None, "the revoked session still works"

    def test_revoking_an_unknown_token_reports_false(self, store: AccountStore) -> None:
        assert store.end_session("khong-phai-token") is False

    def test_revoking_all_sessions_leaves_other_users_alone(self, store: AccountStore) -> None:
        a = _teacher(store, "teacher1")
        b = _teacher(store, "teacher2")
        token_a1, _ = store.start_session(a["id"])
        token_a2, _ = store.start_session(a["id"])
        token_b, _ = store.start_session(b["id"])

        assert store.end_all_sessions(a["id"]) == 2
        assert store.resolve_session(token_a1) is None
        assert store.resolve_session(token_a2) is None
        # b's session is untouched: "sign out everywhere" is per-user.
        assert store.resolve_session(token_b) is not None

    def test_an_expired_session_does_not_resolve_and_is_swept(self, store: AccountStore) -> None:
        user = _teacher(store)
        token, _ = store.start_session(user["id"])

        # Backdate the row rather than sleeping a week: the store must treat
        # expiry as a fact about the row, not about how long the test ran.
        past = (datetime.now(UTC) - timedelta(seconds=1)).isoformat()
        with store._lock:  # noqa: SLF001 - white-box on purpose, see the docstring
            store._require_conn().execute(  # noqa: SLF001
                "UPDATE sessions SET expires_at = ? WHERE token_hash = ?",
                (past, hash_token(token)),
            )
            store._require_conn().commit()  # noqa: SLF001

        assert store.resolve_session(token) is None
        # Swept on read: no timer to forget to run.
        assert store.count_sessions() == 0

    def test_two_sessions_are_independent_tokens(self, store: AccountStore) -> None:
        user = _teacher(store)
        first, _ = store.start_session(user["id"])
        second, _ = store.start_session(user["id"])
        assert first != second
        assert store.count_sessions() == 2

    def test_sessions_are_deleted_with_their_user(self, store: AccountStore) -> None:
        """`ON DELETE CASCADE` — and it must actually be ON.

        SQLite enables foreign keys PER CONNECTION; forgetting the pragma makes
        this table grow orphan rows forever while every other test stays green.
        """
        user = _teacher(store)
        token, _ = store.start_session(user["id"])
        with sqlite3.connect(store.path) as conn:
            conn.execute("PRAGMA foreign_keys=ON")
            conn.execute("DELETE FROM users WHERE id = ?", (user["id"],))
            conn.commit()
        assert store.resolve_session(token) is None
        assert store.count_sessions() == 0

    def test_the_ttl_is_a_named_constant_not_a_magic_number(self, store: AccountStore) -> None:
        user = _teacher(store)
        _, meta = store.start_session(user["id"])
        created = datetime.fromisoformat(meta["createdAt"])
        expires = datetime.fromisoformat(meta["expiresAt"])
        assert expires - created == SESSION_TTL


# ---------------------------------------------------------------- durability


class TestDurability:
    def test_accounts_survive_a_reopen(self, tmp_path: Path) -> None:
        path = tmp_path / "accounts.sqlite3"
        first = AccountStore(path)
        user = first.register("teacher1", "matkhau-du-dai", "teacher")
        token, _ = first.start_session(user["id"])
        first.close()

        second = AccountStore(path)
        assert second.authenticate("teacher1", "matkhau-du-dai")["id"] == user["id"]
        assert second.resolve_session(token) is not None
        second.close()

    def test_an_unwritable_path_raises_rather_than_forgetting_accounts(self, tmp_path: Path) -> None:
        """No memory fallback, and that is a DECISION (ADR-0020).

        `SqliteCache` degrades to memory because a lost cache hit costs money.
        Here it would present itself to every user as "wrong password" at once,
        which is the least debuggable failure a login screen can have — so the
        store refuses instead.
        """
        blocker = tmp_path / "not-a-dir"
        blocker.write_text("i am a file, not a directory")
        with pytest.raises((sqlite3.Error, OSError, NotADirectoryError)):
            AccountStore(blocker / "accounts.sqlite3")


def test_hash_token_is_stable_and_not_the_token() -> None:
    token = "abc123"
    assert hash_token(token) == hash_token(token)
    assert hash_token(token) != token
    assert hash_token(token) == hashlib.sha256(b"abc123").hexdigest()
