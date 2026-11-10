from __future__ import annotations

from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.main import app

VAGUE = {
    "requirement_id": "FR-03",
    "text": "The system shall respond quickly to every search request.",
}


def test_review_with_app_token():
    settings = Settings(app_token="secret-desktop-token", mock_mode=True, gemini_api_key="")
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        with TestClient(app) as c:
            res = c.post(
                "/review",
                json=VAGUE,
                headers={"X-App-Token": "secret-desktop-token", "X-User-Id": "student-1"},
            )
            assert res.status_code == 200
            data = res.json()
            assert data["requirement_id"] == "FR-03"
            assert data["score"] >= 0

            # Wrong token rejects with 401
            bad = c.post(
                "/review",
                json=VAGUE,
                headers={"X-App-Token": "wrong-token"},
            )
            assert bad.status_code == 401
    finally:
        app.dependency_overrides.pop(get_settings, None)


def test_review_batch_with_app_token():
    settings = Settings(app_token="secret-desktop-token", mock_mode=True, gemini_api_key="")
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        with TestClient(app) as c:
            res = c.post(
                "/review/batch",
                json={"units": [VAGUE]},
                headers={"X-App-Token": "secret-desktop-token", "X-User-Id": "student-1"},
            )
            assert res.status_code == 200
            data = res.json()
            assert len(data["results"]) == 1
            assert data["failed"] == []
    finally:
        app.dependency_overrides.pop(get_settings, None)
