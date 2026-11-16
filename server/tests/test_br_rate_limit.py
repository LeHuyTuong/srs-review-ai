"""BR-02-14 — mỗi người tối đa 50 lượt chấm AI/ngày; lượt thứ 51 trả HTTP 429.

Vị trí luật: ``server/app/config/settings.py:108`` (``rate_limit_per_day = 50``)
và ``server/app/api/review.py:74-79`` (thông điệp nguyên văn).

``tests/test_api.py::test_rate_limit_returns_429`` đã kiểm mã 429 với một hạn
mức tiêm vào (1); file này ghim đúng con số 50 của luật, ranh giới 50/51 và
nguyên văn thông điệp — thứ mà test cũ chỉ kiểm một mảnh ("Retry after Ns").
"""

from __future__ import annotations

import re

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.main import _limiter, _review_cache, app


@pytest.fixture(autouse=True)
def _isolate_state(monkeypatch):
    """Hạn mức là singleton theo tiến trình; mỗi test phải bắt đầu từ 0 lượt."""
    monkeypatch.delenv("RATE_LIMIT_PER_DAY", raising=False)
    _review_cache.clear()
    _limiter.reset()
    yield
    _review_cache.clear()
    _limiter.reset()


@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _payload(index: int) -> dict:
    # Mỗi lượt một văn bản khác nhau: trúng cache thì không tiêu hạn mức.
    return {
        "requirement_id": f"BR-02-14-{index}",
        "text": f"The system shall respond quickly to every search request, case {index}.",
        "section": "3.2",
    }


def test_default_daily_limit_is_fifty():
    assert Settings(mock_mode=True, gemini_api_key="").rate_limit_per_day == 50


def test_fiftieth_review_is_allowed_and_fifty_first_returns_429(client):
    for index in range(50):
        allowed = client.post("/review", json=_payload(index))
        assert allowed.status_code == 200, (index, allowed.text)

    blocked = client.post("/review", json=_payload(50))
    assert blocked.status_code == 429

    retry_after = int(blocked.headers["retry-after"])
    assert 0 < retry_after <= 86_400

    detail = blocked.json()["detail"]
    assert detail == f"Daily review limit reached (50). Retry after {retry_after}s."
    assert re.fullmatch(r"Daily review limit reached \(50\)\. Retry after \d+s\.", detail)
