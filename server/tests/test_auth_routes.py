"""/auth/* over real HTTP — ADR-0020's surface, driven through TestClient.

The four claims asserted here, and why each is a route-level test rather than a
store-level one:

* **The cookie is `HttpOnly`, and the browser never sees the token.** A caller
  that reads the session out of the response body would be storing it somewhere
  a script can reach; the assertion is on the `Set-Cookie` header itself.
* **Revocation is visible over HTTP, not just in the store.** Logout, then the
  next `/auth/me` is 401 — the property ADR-0016 gave up and ADR-0020 bought
  back, tested at the layer a user actually experiences it.
* **One 401 for "wrong password" and "no such user".** The store test pins that
  the two exceptions match; this pins that the ROUTE does not accidentally
  distinguish them in status or body.
* **`current_user` refuses without a cookie.** Every protected route depends on
  it, so its 401 is the gate the rest of the app stands on.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.api.accounts import SESSION_COOKIE, current_user, require_teacher
from app.config import Settings, get_settings
from app.infrastructure.accounts import AccountStore
from app.main import app

ACCOUNT = {"username": "gv01", "password": "matkhau-du-dai", "role": "teacher"}


@pytest.fixture
def client(tmp_path: Path, monkeypatch):
    """A fresh account store per test, and a fresh cookie jar.

    Both halves are load-bearing. The account store lives in the shared
    `SRS_CACHE_DIR`, so without the swap the SECOND test to register `gv01` gets
    a 409 — every test in this file failed with "username 'gv01' is taken"
    until this fixture existed. That is the same class of bug conftest.py's
    docstring warns about for the review cache, and it is worth stating: a
    shared on-disk store turns "the tests each set up their own world" into a
    lie that only shows up from the second test onward.
    """
    store = AccountStore(tmp_path / "accounts.sqlite3")
    monkeypatch.setattr(main_module, "_account_store", store)
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    store.close()


def _register(client: TestClient, **overrides) -> dict:
    payload = {**ACCOUNT, **overrides}
    response = client.post("/auth/register", json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def _login(client: TestClient, username: str = "gv01", password: str | None = None):
    # A `None` sentinel rather than a literal default: a password-shaped
    # default in a signature is exactly what ruff's S107 flags, and the
    # right fix is to stop writing one, not to silence the rule.
    if password is None:
        password = ACCOUNT["password"]
    return client.post("/auth/login", json={"username": username, "password": password})


# ---------------------------------------------------------------- register


class TestRegisterRoute:
    def test_creates_an_account_without_returning_password_material(self, client) -> None:
        body = _register(client)
        assert body["username"] == "gv01"
        assert body["role"] == "teacher"
        assert "password" not in body and "password_hash" not in body
        assert "id" in body

    def test_does_not_log_in(self, client) -> None:
        # Registration and authentication are separate acts. A 201 that also
        # set a cookie would hide the case where the second one would fail.
        _register(client)
        assert client.get("/auth/me").status_code == 401

    def test_a_duplicate_username_is_409(self, client) -> None:
        _register(client)
        assert client.post("/auth/register", json=ACCOUNT).status_code == 409

    @pytest.mark.parametrize(
        "bad",
        [
            {"username": "ab"},  # too short for the store's rule
            {"username": "x" * 65},
            {"password": "ngan"},  # too short for the store's rule
            {"role": "admin"},  # not a role this app has
            {"role": "Teacher"},  # case matters; a typo must not become a new role
        ],
    )
    def test_bad_input_is_rejected(self, client, bad: dict) -> None:
        # Note the two sources of 422 on purpose: pydantic rejects an unknown
        # ROLE (Literal) and a too-long username (max_length) before the store
        # sees it, while a too-short username/password is the store's rule.
        # Both must land on the same status so a caller has ONE bad-input branch.
        assert client.post("/auth/register", json={**ACCOUNT, **bad}).status_code == 422

    def test_an_extra_field_is_rejected(self, client) -> None:
        # `extra="forbid"`: a client sending `isAdmin` must be told it is not
        # understood, not have it silently dropped.
        response = client.post("/auth/register", json={**ACCOUNT, "isAdmin": True})
        assert response.status_code == 422


# ---------------------------------------------------------------- login


class TestLoginRoute:
    def test_valid_credentials_set_an_httponly_cookie(self, client) -> None:
        _register(client)
        response = _login(client)
        assert response.status_code == 200
        assert response.json()["role"] == "teacher"
        # The token must NOT be in the body.
        assert "token" not in response.json()

        raw = response.headers["set-cookie"]
        assert SESSION_COOKIE in raw
        assert "HttpOnly" in raw, "the session cookie is readable by scripts"
        # Case-insensitive both sides — the header spells it `SameSite=lax`
        # while an assertion written as `"SameSite=lax" in raw.lower()` compares
        # a mixed-case needle to a lowered haystack and can never match.
        lowered = raw.lower()
        assert "samesite=lax" in lowered, "the session cookie lost its CSRF protection"
        # And it must NOT be `None`: SameSite=None drops the cross-site
        # protection Lax gives for top-level navigations, which is exactly the
        # flow a browser login uses.
        assert "samesite=none" not in lowered

    def test_the_cookie_is_not_secure_by_default_so_localhost_can_log_in(self, client) -> None:
        # A hard-coded Secure flag makes every http://localhost login silently
        # fail to persist. The flag is settings-driven; this pins the default.
        _register(client)
        raw = _login(client).headers["set-cookie"]
        assert "Secure" not in raw

    def test_a_wrong_password_and_an_unknown_user_are_the_same_response(self, client) -> None:
        _register(client)
        wrong = _login(client, password="sai-mat-khau")
        unknown = _login(client, username="khong-ton-tai", password="sai-mat-khau")
        assert wrong.status_code == unknown.status_code == 401
        assert wrong.json() == unknown.json(), "the login route leaks which usernames exist"

    def test_logging_in_twice_yields_two_independent_sessions(self, client) -> None:
        _register(client)
        first = _login(client).headers["set-cookie"]
        second = _login(client).headers["set-cookie"]
        assert first != second


# ---------------------------------------------------------------- me


class TestMeRoute:
    def test_401_without_a_cookie(self, client) -> None:
        response = client.get("/auth/me")
        assert response.status_code == 401
        assert response.json()["detail"] == "not signed in"

    def test_401_for_an_unknown_token(self, client) -> None:
        client.cookies.set(SESSION_COOKIE, "khong-phai-token")
        assert client.get("/auth/me").status_code == 401

    def test_returns_the_signed_in_user(self, client) -> None:
        created = _register(client)
        _login(client)
        body = client.get("/auth/me").json()
        assert body["id"] == created["id"]
        assert body["username"] == "gv01"
        assert body["role"] == "teacher"


# ---------------------------------------------------------------- logout


class TestLogoutRoute:
    def test_logout_kills_the_session_immediately(self, client) -> None:
        """ADR-0020's headline property, over HTTP."""
        _register(client)
        _login(client)
        assert client.get("/auth/me").status_code == 200

        assert client.post("/auth/logout").status_code == 200
        assert client.get("/auth/me").status_code == 401, "the session survived logout"

    def test_logout_without_a_session_is_not_an_error(self, client) -> None:
        # A 401 here would leave a browser unable to clear its own dead cookie.
        assert client.post("/auth/logout").status_code == 200

    def test_logout_clears_the_cookie(self, client) -> None:
        _register(client)
        _login(client)
        raw = client.post("/auth/logout").headers["set-cookie"]
        # An expired/blank value is how a cookie is deleted.
        assert SESSION_COOKIE in raw
        assert '=""' in raw or "Max-Age=0" in raw or "expires=" in raw.lower()


# ---------------------------------------------------------------- gates


class TestRoleGates:
    """`current_user` / `require_teacher` as the gate the rest of the app takes.

    These drive the dependency directly through a throwaway route rather than
    through `/auth/me`, because the point is the DEPENDENCY's behaviour: a route
    that forgets it is a route with no gate, and these are the two the routes
    will import.
    """

    def test_current_user_rejects_a_missing_cookie(self) -> None:
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc:
            current_user(session_token=None)
        assert exc.value.status_code == 401

    def test_current_user_rejects_an_unknown_token(self) -> None:
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc:
            current_user(session_token="khong-phai-token")
        assert exc.value.status_code == 401

    def test_require_teacher_refuses_a_student(self) -> None:
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc:
            require_teacher(user={"id": "u1", "username": "sv01", "role": "student"})
        assert exc.value.status_code == 403

    def test_require_teacher_admits_a_teacher(self) -> None:
        teacher = {"id": "u1", "username": "gv01", "role": "teacher"}
        assert require_teacher(user=teacher) is teacher
