"""Accounts and sessions — the identity ADR-0016 deliberately did without.

Why this file exists (ADR-0020)
===============================
ADR-0016 chose a class `class_id` capability INSTEAD of accounts, and said why:
"schema + auth + recovery, with no consumer yet". ADR-0020 reverses that choice
on the owner's instruction, so the consumer now exists and this file is it. The
reversal is recorded, not silent — see `docs/adr/0020-*`.

What this store does, and the two things it refuses to do
========================================================
* **Passwords are hashed with `scrypt` from the standard library**, one salt per
  account, and compared with `secrets.compare_digest`. No `bcrypt`/`argon2`
  dependency: ADR-0011 established the precedent (stdlib first, add a dependency
  when a measurement asks for one), and the cost is stated in ADR-0020 rather
  than hidden — stdlib scrypt's default parameters are weaker than argon2id.
* **Sessions are opaque random tokens, stored HASHED.** A copy of this database
  does not yield a usable session, exactly as a copy of the class store does not
  yield a write key. This is the whole reason a session is a row and not a JWT:
  a row can be deleted, and deletion is the revocation ADR-0016 could not offer.
* **It does NOT fall back to memory when the file is unwritable.** The
  `SqliteCache` degradation in `store.py` is right for a cache — a lost hit
  costs money, a hard failure costs a review. It is wrong here: an auth store
  that silently forgets every account is worse than one that refuses to start,
  because the failure looks like "wrong password" to every user at once.

Framework-free, like the other stores: the routes own the HTTP, this owns the
bytes.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import sqlite3
import threading
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Final

# ---------------------------------------------------------------- tuning

# scrypt parameters. n=2**14 is the value that has been the common floor since
# 2016 (it is what `hashlib.scrypt`'s own docs use); raising it is a one-line
# change and costs login latency, which is the right lever for this decision.
#
# n MUST be a power of 2 for scrypt, and `maxmem` has to be raised past the
# default 32 MiB or a legitimate login raises "memory limit exceeded" — the
# requirement is roughly 128 * n * r bytes = 128 * 16384 * 8 = 16 MiB for the
# hashing itself, but OpenSSL's accounting overshoots and 32 MiB is too tight.
_SCRYPT_N: Final = 2**14
_SCRYPT_R: Final = 8
_SCRYPT_P: Final = 1
_SCRYPT_DKLEN: Final = 64
_SCRYPT_MAXMEM: Final = 64 * 1024 * 1024

_SALT_BYTES: Final = 16
_SESSION_BYTES: Final = 32

# A stored password is `scrypt$n$r$p$<b64 salt>$<b64 hash>`. The parameters ride
# WITH the hash so they can be raised later without invalidating old rows —
# `verify_password` reads them from the row it is checking.
_HASH_SCHEME: Final = "scrypt"

# Sessions live a week. Long enough that a teacher is not re-typing during a
# marking week, short enough that an abandoned laptop is not a permanent key.
SESSION_TTL: Final = timedelta(days=7)

# Deliberately permissive: usernames are a label, not an email. The store only
# refuses what would break the file or confuse a lookup.
_USERNAME_RE: Final = re.compile(r"^[A-Za-z0-9._@-]{3,64}$")

USERNAME_MIN: Final = 3
USERNAME_MAX: Final = 64
PASSWORD_MIN: Final = 8

ROLES: Final = ("teacher", "student")


# ---------------------------------------------------------------- errors


class AccountError(Exception):
    """Base for this store's failures."""


class InvalidCredentialsError(AccountError):
    """Wrong username or wrong password — deliberately the SAME error.

    Distinguishing the two tells an attacker which usernames exist, which is a
    free enumeration oracle. The route maps both to one 401 with one message,
    and a test pins that they are indistinguishable.
    """


class UsernameTakenError(AccountError):
    """The username is already registered."""


class InvalidAccountInputError(AccountError):
    """A field the store will not store: bad username shape, short password, unknown role."""


class NoSessionError(AccountError):
    """No live session under that token — expired, revoked, or never issued."""


# ---------------------------------------------------------------- hashing


def hash_password(password: str, *, salt: bytes | None = None) -> str:
    """Return a self-describing scrypt hash of ``password``.

    The parameters are embedded so a future raise of ``_SCRYPT_N`` does not
    invalidate stored rows: verification reads them back from the row.
    """
    salt = salt or secrets.token_bytes(_SALT_BYTES)
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=_SCRYPT_N,
        r=_SCRYPT_R,
        p=_SCRYPT_P,
        dklen=_SCRYPT_DKLEN,
        maxmem=_SCRYPT_MAXMEM,
    )
    import base64

    return "$".join(
        (
            _HASH_SCHEME,
            str(_SCRYPT_N),
            str(_SCRYPT_R),
            str(_SCRYPT_P),
            base64.b64encode(salt).decode("ascii"),
            base64.b64encode(digest).decode("ascii"),
        )
    )


def verify_password(password: str, stored: str) -> bool:
    """Check ``password`` against a stored hash, never raising on a malformed row.

    A row this build cannot parse is a failed login, not a crash: the alternative
    is an account nobody can use AND nobody can diagnose from the outside.
    """
    import base64

    try:
        scheme, n, r, p, salt_b64, hash_b64 = stored.split("$")
        if scheme != _HASH_SCHEME:
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(hash_b64)
        digest = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(expected),
            maxmem=_SCRYPT_MAXMEM,
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest, expected)


def hash_token(token: str) -> str:
    """Sessions are stored hashed, so a database copy is not a set of live keys.

    sha256 without a salt is right HERE and wrong for passwords: a session token
    is 256 bits of machine randomness (nothing to guess or rainbow), and it must
    be lookups-by-value, which a per-row salt would forbid.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------- store


class AccountStore:
    """`users` and `sessions` on SQLite, beside the review cache.

    One connection, one lock: the app runs on a single event loop thread, but a
    test client drives requests from a worker thread — the same arrangement
    `SqliteCache` uses, for the same reason.
    """

    def __init__(self, path: Path) -> None:
        self._path = Path(path)
        self._lock = threading.Lock()
        self._conn: sqlite3.Connection | None = None
        self._open()

    # ------------------------------------------------------------ lifecycle

    def _open(self) -> None:
        """Create the schema. Raises if the file cannot be used.

        No memory fallback, on purpose — see the module docstring. An auth store
        that loses accounts silently presents itself as "wrong password", which
        is the least debuggable failure a login screen can have.
        """
        self._path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self._path, check_same_thread=False, timeout=5.0)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id            TEXT PRIMARY KEY,
                username      TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                role          TEXT NOT NULL,
                created_at    TEXT NOT NULL,
                class_id      TEXT,
                grp           TEXT
            )
            """
        )
        # `CREATE TABLE IF NOT EXISTS` does NOT add a column to a table that
        # already exists, so a database written before these two columns keeps
        # its old shape and every read of `class_id` raises. The ALTERs below
        # are idempotent (guarded by a PRAGMA read), which is what makes this a
        # migration rather than a "delete your database" instruction.
        self._ensure_column(conn, "users", "class_id", "TEXT")
        self._ensure_column(conn, "users", "grp", "TEXT")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL
            )
            """
        )
        # Lookups are by token (the PK) and expiry sweeps by expires_at.
        conn.execute("CREATE INDEX IF NOT EXISTS sessions_by_expiry ON sessions (expires_at)")
        conn.commit()
        self._conn = conn

    def close(self) -> None:
        with self._lock:
            if self._conn is not None:
                self._conn.close()
                self._conn = None

    @property
    def path(self) -> Path:
        return self._path

    @staticmethod
    def _ensure_column(conn: sqlite3.Connection, table: str, column: str, decl: str) -> None:
        """Add a column only when it is missing.

        SQLite has no `ADD COLUMN IF NOT EXISTS`, and a blind `ALTER TABLE`
        raises "duplicate column name" on the second open — which would make the
        store unusable after one restart. Reading `PRAGMA table_info` first is
        what makes the migration idempotent.
        """
        existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
        if column not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")
            conn.commit()

    # ------------------------------------------------------------ accounts

    def register(
        self,
        username: str,
        password: str,
        role: str,
        *,
        class_id: str | None = None,
        group: str | None = None,
    ) -> dict[str, Any]:
        """Create an account. Returns the row WITHOUT the password hash.

        The hash never leaves this method: a caller that never receives it
        cannot log it.

        `class_id` (a teacher's class) and `group` (a student's group) are what
        make `GET /submissions` meaningful — they are the two facts a list can
        be filtered by. They are passed at registration because there is no
        assignment screen (ADR-0020 §Consequences records that as not built).
        """
        username = username.strip()
        if not _USERNAME_RE.match(username):
            raise InvalidAccountInputError(
                f"username must be {USERNAME_MIN}-{USERNAME_MAX} characters of "
                "letters, digits, dot, underscore, @ or hyphen"
            )
        if len(password) < PASSWORD_MIN:
            raise InvalidAccountInputError(f"password must be at least {PASSWORD_MIN} characters")
        if role not in ROLES:
            raise InvalidAccountInputError(f"role must be one of {ROLES}")

        user_id = secrets.token_urlsafe(16)
        created_at = _now()
        with self._lock:
            conn = self._require_conn()
            try:
                conn.execute(
                    "INSERT INTO users (id, username, password_hash, role, created_at, class_id, grp) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (
                        user_id,
                        username,
                        hash_password(password),
                        role,
                        created_at,
                        class_id.strip() if class_id else None,
                        group.strip() if group else None,
                    ),
                )
                conn.commit()
            except sqlite3.IntegrityError as exc:
                # UNIQUE(username). The only integrity rule that can fire here.
                raise UsernameTakenError(f"username {username!r} is taken") from exc
        return {
            "id": user_id,
            "username": username,
            "role": role,
            "createdAt": created_at,
            "classId": class_id.strip() if class_id else None,
            "group": group.strip() if group else None,
        }

    def authenticate(self, username: str, password: str) -> dict[str, Any]:
        """Return the user row for valid credentials, else raise ONE error.

        Both failure modes raise `InvalidCredentialsError` with the same message,
        so the response cannot be used to enumerate usernames.
        """
        with self._lock:
            row = (
                self._require_conn()
                .execute(
                    "SELECT id, username, password_hash, role, created_at, class_id, grp "
                    "FROM users WHERE username = ?",
                    (username.strip(),),
                )
                .fetchone()
            )
        # Verify even when the row is missing: an early return on "no such user"
        # makes the timing difference a username oracle, which is exactly what
        # the shared error message is meant to prevent.
        stored = row[2] if row else _DUMMY_HASH
        if not verify_password(password, stored) or row is None:
            raise InvalidCredentialsError("invalid username or password")
        return {
            "id": row[0],
            "username": row[1],
            "role": row[3],
            "createdAt": row[4],
            "classId": row[5],
            "group": row[6],
        }

    def get_user(self, user_id: str) -> dict[str, Any] | None:
        with self._lock:
            row = (
                self._require_conn()
                .execute(
                    "SELECT id, username, role, created_at, class_id, grp FROM users WHERE id = ?",
                    (user_id,),
                )
                .fetchone()
            )
        if row is None:
            return None
        return {
            "id": row[0],
            "username": row[1],
            "role": row[2],
            "createdAt": row[3],
            "classId": row[4],
            "group": row[5],
        }

    def find_by_username(self, username: str) -> dict[str, Any] | None:
        with self._lock:
            row = (
                self._require_conn()
                .execute(
                    "SELECT id, username, role, created_at, class_id, grp FROM users WHERE username = ?",
                    (username.strip(),),
                )
                .fetchone()
            )
        if row is None:
            return None
        return {
            "id": row[0],
            "username": row[1],
            "role": row[2],
            "createdAt": row[3],
            "classId": row[4],
            "group": row[5],
        }

    def set_membership(
        self, user_id: str, *, class_id: str | None = None, group: str | None = None
    ) -> dict[str, Any] | None:
        """Attach a teacher's class or a student's group to an account.

        Exists because a user created before these columns (or by a caller that
        did not supply them) would otherwise be permanently invisible to
        `GET /submissions` with no way to fix it short of editing the database
        by hand. Returns the updated row, or None if there is no such user.
        """
        with self._lock:
            conn = self._require_conn()
            cursor = conn.execute(
                "UPDATE users SET class_id = ?, grp = ? WHERE id = ?",
                (
                    class_id.strip() if class_id else None,
                    group.strip() if group else None,
                    user_id,
                ),
            )
            conn.commit()
            if cursor.rowcount == 0:
                return None
        return self.get_user(user_id)

    def count_users(self) -> int:
        with self._lock:
            row = self._require_conn().execute("SELECT COUNT(*) FROM users").fetchone()
        return int(row[0]) if row else 0

    # ------------------------------------------------------------ sessions

    def start_session(self, user_id: str) -> tuple[str, dict[str, Any]]:
        """Mint a session. Returns the PLAINTEXT token — this is the only moment
        it exists server-side, exactly like a class `write_key`."""
        token = secrets.token_urlsafe(_SESSION_BYTES)
        # ONE clock read for both stamps. Two `datetime.now()` calls a
        # microsecond apart made `expires - created` differ from SESSION_TTL by
        # 1 µs — enough to break an exact assertion, and a sign that "when this
        # session started" was being answered twice with different answers.
        created = _now()
        expires = (created + SESSION_TTL).isoformat()
        with self._lock:
            conn = self._require_conn()
            conn.execute(
                "INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (hash_token(token), user_id, created.isoformat(), expires),
            )
            conn.commit()
        return token, {"createdAt": created.isoformat(), "expiresAt": expires}

    def resolve_session(self, token: str) -> dict[str, Any] | None:
        """Return the user behind a live token, or None.

        Expired rows are deleted on read: an expired session that still resolves
        is the bug this method exists to make impossible, and sweeping here means
        there is no timer to forget to run.
        """
        if not token:
            return None
        token_hash = hash_token(token)
        with self._lock:
            conn = self._require_conn()
            row = conn.execute(
                "SELECT s.user_id, s.expires_at, u.username, u.role, u.created_at, "
                "       u.class_id, u.grp "
                "FROM sessions s JOIN users u ON u.id = s.user_id "
                "WHERE s.token_hash = ?",
                (token_hash,),
            ).fetchone()
            if row is None:
                return None
            if _parse(row[1]) <= datetime.now(UTC):
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash,))
                conn.commit()
                return None
        # The membership columns MUST be selected here, not just stored: this is
        # the row every authenticated route receives as its `user`, and a field
        # the store holds but this SELECT omits is invisible to the whole app.
        # It cost a debugging round — `GET /submissions` returned an empty list
        # for a teacher who had a class, because `user["classId"]` was silently
        # absent. Same whitelist trap AGENTS.md records for the submission read
        # view; a new column means a new SELECT and a test that reads it back
        # THROUGH the route.
        return {
            "id": row[0],
            "username": row[2],
            "role": row[3],
            "createdAt": row[4],
            "classId": row[5],
            "group": row[6],
        }

    def end_session(self, token: str) -> bool:
        """Revoke one session. Returns whether a row was actually removed."""
        if not token:
            return False
        with self._lock:
            conn = self._require_conn()
            cursor = conn.execute("DELETE FROM sessions WHERE token_hash = ?", (hash_token(token),))
            conn.commit()
            return cursor.rowcount > 0

    def end_all_sessions(self, user_id: str) -> int:
        with self._lock:
            conn = self._require_conn()
            cursor = conn.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
            conn.commit()
            return cursor.rowcount

    def count_sessions(self) -> int:
        with self._lock:
            row = self._require_conn().execute("SELECT COUNT(*) FROM sessions").fetchone()
        return int(row[0]) if row else 0

    def sweep_expired(self) -> int:
        with self._lock:
            conn = self._require_conn()
            cursor = conn.execute("DELETE FROM sessions WHERE expires_at <= ?", (_now().isoformat(),))
            conn.commit()
            return cursor.rowcount

    # ------------------------------------------------------------ internals

    def _require_conn(self) -> sqlite3.Connection:
        if self._conn is None:
            raise AccountError("account store is closed")
        return self._conn


# ---------------------------------------------------------------- helpers


def _now() -> datetime:
    return datetime.now(UTC)


def _parse(value: str) -> datetime:
    """Parse a stored ISO timestamp, treating a naive one as UTC.

    `datetime.fromisoformat` on a value written by an older build (no offset)
    returns a naive datetime, and comparing that to an aware one raises — the
    kind of failure that only appears once a real deployment has old rows.
    """
    parsed = datetime.fromisoformat(value)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def open_account_store(path: Path) -> AccountStore:
    return AccountStore(path)


# A hash of a fixed password, used to keep `authenticate` constant-ish in the
# "no such user" case. Computed once at import: it is never verified against a
# real password, only against the attacker's guess.
_DUMMY_HASH: Final = hash_password("not-a-real-password")


def dummy_verifier() -> Callable[[str], bool]:
    """Test seam: a verifier that always fails, for timing-shape tests."""
    return lambda _password: False


__all__ = [
    "PASSWORD_MIN",
    "ROLES",
    "SESSION_TTL",
    "AccountError",
    "AccountStore",
    "InvalidAccountInputError",
    "InvalidCredentialsError",
    "NoSessionError",
    "UsernameTakenError",
    "dummy_verifier",
    "hash_password",
    "hash_token",
    "open_account_store",
    "verify_password",
]
