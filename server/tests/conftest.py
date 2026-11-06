"""Test-session setup.

`SRS_CACHE_DIR` is redirected to a throwaway directory *before* `app.main` is
imported, because the durable cache is opened at import time. Without this the
suite would read and — worse — `clear()` the real development cache under
`server/.cache/`, which on 2026-09-22 held 238 paid-for review results.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest

_CACHE_DIR = Path(tempfile.mkdtemp(prefix="srs-review-test-cache-"))
os.environ["SRS_CACHE_DIR"] = str(_CACHE_DIR)

# Tests must not read the developer's `server/.env`: real GEMINI/GOOGLE_API_KEY_n
# values there leaked into key-rotation tests (extra keys, live cooldowns) and
# made 14 tests depend on whoever ran them. Each test sets what it needs.
from app.config.settings import Settings  # noqa: E402

Settings.model_config["env_file"] = None


@pytest.fixture(autouse=True)
def _verified_firebase_test_user():
    """Keep endpoint tests offline while routes require verified identity."""
    from app.core.firebase_auth import verify_firebase_token
    from app.main import app

    previous = app.dependency_overrides.get(verify_firebase_token)
    app.dependency_overrides[verify_firebase_token] = lambda: {"uid": "test-user"}
    yield
    if previous is None:
        app.dependency_overrides.pop(verify_firebase_token, None)
    else:
        app.dependency_overrides[verify_firebase_token] = previous
