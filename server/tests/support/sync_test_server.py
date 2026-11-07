"""Real FastAPI app for the mobile offline-sync integration test — TEST ONLY.

Started by ``mobile/test/offline_sync_test.dart``. Everything is the
production app except Firebase verification, replaced by ``Bearer test:<uid>``
so the test needs no Google credentials. Never deploy this file: it accepts
any uid the caller names.

Usage: ``SRS_CACHE_DIR=<tmp> DATABASE_URL= python tests/support/sync_test_server.py <port>``
(cwd = ``server/``).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import uvicorn  # noqa: E402
from fastapi import Header, HTTPException  # noqa: E402

from app.core.firebase_auth import verify_firebase_token  # noqa: E402
from app.main import app  # noqa: E402


def _test_identity(authorization: str | None = Header(default=None)) -> dict:
    prefix = "Bearer test:"
    if not authorization or not authorization.startswith(prefix) or len(authorization) == len(prefix):
        raise HTTPException(status_code=401, detail="test server wants 'Bearer test:<uid>'")
    return {"uid": authorization[len(prefix) :]}


app.dependency_overrides[verify_firebase_token] = _test_identity

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(sys.argv[1]), log_level="warning")
