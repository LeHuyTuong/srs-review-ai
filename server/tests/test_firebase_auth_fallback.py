"""Firebase ID-token verification when the server has no service-account key.

Bug (2026-11-10, Artemis run on a real phone): with no Application Default
Credentials every authenticated call — /sync/push, /review, /review/batch —
answered 500 (DefaultCredentialsError escaped), so the phone saw "server error"
for a perfectly valid token. Verifying a token only needs Google's public certs;
the key file is only needed to *send* (FCM).
"""

from __future__ import annotations

import google.auth.exceptions
import pytest
from fastapi import HTTPException

from app.config.settings import Settings
from app.core import firebase_auth

PID = "demo-project"


@pytest.fixture
def no_adc(monkeypatch):
    def boom(*_a, **_k):
        raise google.auth.exceptions.DefaultCredentialsError("no key on this machine")

    monkeypatch.setattr(firebase_auth.auth, "verify_id_token", boom)


def _claims(**over):
    return {"iss": f"https://securetoken.google.com/{PID}", "aud": PID, "sub": "uid-1", **over}


def test_valid_token_is_accepted_through_public_keys(no_adc, monkeypatch):
    seen = {}

    def verify(token, _req, audience):
        seen["audience"] = audience
        return _claims()

    monkeypatch.setattr(firebase_auth.google.oauth2.id_token, "verify_firebase_token", verify)
    decoded = firebase_auth.decode_id_token("tok", Settings(firebase_project_id=PID))
    assert decoded["uid"] == "uid-1"
    assert seen["audience"] == PID


@pytest.mark.parametrize(
    "claims",
    [
        _claims(iss="https://securetoken.google.com/someone-else"),
        _claims(sub=""),
        None,
    ],
)
def test_wrong_issuer_or_subject_is_401(no_adc, monkeypatch, claims):
    monkeypatch.setattr(firebase_auth.google.oauth2.id_token, "verify_firebase_token", lambda *a, **k: claims)
    with pytest.raises(HTTPException) as err:
        firebase_auth.decode_id_token("tok", Settings(firebase_project_id=PID))
    assert err.value.status_code == 401


def test_bad_signature_or_expired_is_401(no_adc, monkeypatch):
    def verify(*_a, **_k):
        raise ValueError("Token expired")

    monkeypatch.setattr(firebase_auth.google.oauth2.id_token, "verify_firebase_token", verify)
    with pytest.raises(HTTPException) as err:
        firebase_auth.decode_id_token("tok", Settings(firebase_project_id=PID))
    assert err.value.status_code == 401


def test_no_key_and_no_project_id_is_503_not_500(no_adc):
    with pytest.raises(HTTPException) as err:
        firebase_auth.decode_id_token("tok", Settings(firebase_project_id=""))
    assert err.value.status_code == 503
