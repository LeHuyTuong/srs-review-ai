"""Firestore `assets` index — the one writer of that collection.

Clients cannot create these rows (firestore.rules: create false); only this
server, through the Firebase Admin SDK, records an asset after it has verified
the bytes with Cloudinary. Admin Web reads the collection ordered by
``uploadedAt``.

``firebase_admin`` is imported lazily: the test suite and a server without
Cloudinary configured must never need Google credentials just to import.
"""

from __future__ import annotations

import threading
from typing import Any, Protocol

COLLECTION = "assets"


class ReportIndexError(RuntimeError):
    """Firestore write failed — the asset exists, finalize may be retried."""


class ReportIndex(Protocol):
    def record(self, doc_id: str, data: dict[str, Any]) -> None:
        """Upsert ``assets/{doc_id}``; ``uploadedAt`` is set server-side."""


class FirestoreReportIndex:
    """Admin SDK writer. Credentials: Application Default Credentials."""

    def __init__(self, project_id: str) -> None:
        self._project_id = project_id
        self._client: Any = None
        self._lock = threading.Lock()

    def _db(self) -> Any:
        with self._lock:
            if self._client is None:
                import firebase_admin
                from firebase_admin import firestore

                app_name = f"srs-reports-{self._project_id}"
                try:
                    app = firebase_admin.get_app(app_name)
                except ValueError:
                    options = {"projectId": self._project_id}
                    app = firebase_admin.initialize_app(options=options, name=app_name)
                self._client = firestore.client(app)
            return self._client

    def record(self, doc_id: str, data: dict[str, Any]) -> None:
        try:
            from firebase_admin import firestore

            # Same doc id on a retried finalize => the row is overwritten, never duplicated.
            document = self._db().collection(COLLECTION).document(doc_id)
            document.set({**data, "uploadedAt": firestore.SERVER_TIMESTAMP})
        except Exception as exc:  # noqa: BLE001 - every SDK/credential failure means "not recorded"
            raise ReportIndexError(f"Firestore write failed: {type(exc).__name__}") from exc


class InMemoryReportIndex:
    """Test double; keeps rows so a test can assert exactly what was written."""

    def __init__(self) -> None:
        self.rows: dict[str, dict[str, Any]] = {}

    def record(self, doc_id: str, data: dict[str, Any]) -> None:
        self.rows[doc_id] = {**data, "uploadedAt": "SERVER_TIMESTAMP"}
