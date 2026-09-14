"""Presigned-upload pipeline: roundtrip + security tests.

Follows the existing fixture style in test_api.py — patch
``app.dependency_overrides[get_settings]`` for auth config and monkeypatch
``main_module._upload_store`` for an isolated disk-backed store.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import Settings, get_settings
from app.main import app
from app.uploads import UploadStore

APP_TOKEN = "test-app-secret"


@pytest.fixture
def make_client(tmp_path: Path, monkeypatch):
    """Factory: build an isolated, disk-backed UploadStore + TestClient.

    Each call yields ``(client, store)`` with a fresh temp directory so tests
    never clobber each other or the real ``.uploads/`` dir on disk.
    """

    def _make(*, max_bytes: int = 40 * 1024 * 1024, secret: str = APP_TOKEN):
        store = UploadStore(
            upload_dir=tmp_path / "uploads",
            max_bytes=max_bytes,
            secret=secret,
        )
        monkeypatch.setattr(main_module, "_upload_store", store)
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=True, gemini_api_key="", app_token=secret
        )
        return TestClient(app), store

    yield _make
    app.dependency_overrides.clear()


def _presign(client: TestClient, file_name: str = "doc.pdf", size_bytes: int = 4):
    resp = client.post(
        "/uploads/presign",
        json={"file_name": file_name, "size_bytes": size_bytes},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert resp.status_code == 200, resp.json()
    return resp.json()


def _key_from_uri(upload_uri: str) -> str:
    return upload_uri.rsplit("/", 1)[-1]


# --------------------------------------------------------------------------- #
# Roundtrip


def test_presign_put_meta_roundtrip_stores_exact_bytes(make_client):
    client, _ = make_client()
    content = b"hello SRS world"
    expected_sha = hashlib.sha256(content).hexdigest()

    # 1. Ask the server for a presigned capability token.
    presigned = _presign(client, file_name="doc.pdf", size_bytes=len(content))
    key = _key_from_uri(presigned["upload_uri"])
    assert presigned["method"] == "PUT"
    assert presigned["upload_token"]
    assert presigned["expires_at"]

    # 2. PUT the raw bytes — auth is the token, NOT the app token.
    put_resp = client.put(
        presigned["put_url"],
        content=content,
    )
    assert put_resp.status_code == 201
    put_body = put_resp.json()
    assert put_body["key"] == key
    assert put_body["size"] == len(content)
    assert put_body["sha256"] == expected_sha

    # 3. Fetch metadata and confirm the hash matches the exact bytes.
    meta_resp = client.get(
        f"/uploads/{key}/meta", headers={"X-App-Token": APP_TOKEN}
    )
    assert meta_resp.status_code == 200
    meta = meta_resp.json()
    assert meta["sha256"] == expected_sha
    assert meta["size"] == len(content)


# --------------------------------------------------------------------------- #
# Security: token tampering / expiry


def test_put_rejects_tampered_token(make_client):
    client, _ = make_client()
    presigned = _presign(client, size_bytes=4)
    key = _key_from_uri(presigned["upload_uri"])
    token = presigned["upload_token"]

    # Flip one character in the signature half of the token.
    head, _, sig = token.partition(".")
    flipped = "A" if sig[0] != "A" else "B"
    tampered = f"{head}.{flipped}{sig[1:]}"

    resp = client.put(
        f"/uploads/{key}?token={tampered}", content=b"hello"
    )
    assert resp.status_code == 403
    # And nothing was stored.
    assert not (main_module._upload_store._key_path(key).exists())


def test_put_rejects_expired_token(make_client):
    client, store = make_client()
    # Mint a token that was already expired at creation time.
    key = store.generate_key("doc.pdf")
    token, _ = store.create_token(key=key, size=4, ttl_seconds=-1)

    resp = client.put(f"/uploads/{key}?token={token}", content=b"hello")
    assert resp.status_code == 403


def test_put_without_token_is_403(make_client):
    client, _ = make_client()
    key = "some-key"
    resp = client.put(f"/uploads/{key}", content=b"hello")
    assert resp.status_code == 403


def test_put_rejects_token_for_wrong_key(make_client):
    """A token signed for key A cannot be reused against key B."""
    client, store = make_client()
    key_a = store.generate_key("doc-a.pdf")
    key_b = store.generate_key("doc-b.pdf")
    token_a, _ = store.create_token(key=key_a, size=4)

    resp = client.put(f"/uploads/{key_b}?token={token_a}", content=b"hello")
    assert resp.status_code == 403


# --------------------------------------------------------------------------- #
# Security: upload ceiling enforced mid-stream


def test_presign_rejects_oversized_declaration(make_client):
    client, _ = make_client(max_bytes=16)
    resp = client.post(
        "/uploads/presign",
        json={"file_name": "big.bin", "size_bytes": 17},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert resp.status_code == 413


def test_put_over_max_leaves_no_partial_file(make_client):
    client, store = make_client(max_bytes=16)
    presigned = _presign(client, size_bytes=4)
    key = _key_from_uri(presigned["upload_uri"])

    # Stream way more than the 16-byte ceiling.
    resp = client.put(presigned["put_url"], content=b"x" * 1_000)
    assert resp.status_code == 413

    # No final file, no leftover .part sidecar.
    assert not store._key_path(key).exists()
    assert not list(store.upload_dir.glob("*.part"))


# --------------------------------------------------------------------------- #
# Security: path traversal


def test_file_name_cannot_influence_storage_key(make_client):
    """The client-supplied ``file_name`` must NEVER reach the storage path."""
    client, store = make_client()
    presigned = _presign(client, file_name="../../etc/passwd", size_bytes=4)
    key = _key_from_uri(presigned["upload_uri"])

    # The key is server-generated: uuid + sanitized basename, no traversal.
    assert "/" not in key
    assert "\\" not in key
    assert ".." not in key
    assert "passwd" in key  # basename preserved but sanitized

    # Complete the upload to prove it lands safely inside the upload dir.
    put_resp = client.put(presigned["put_url"], content=b"root")
    assert put_resp.status_code == 201
    stored = store._key_path(key)
    assert stored.resolve().is_relative_to(store.upload_dir.resolve())
    assert stored.read_bytes() == b"root"


def test_meta_unknown_key_is_404(make_client):
    client, _ = make_client()
    resp = client.get(
        "/uploads/does-not-exist/meta", headers={"X-App-Token": APP_TOKEN}
    )
    assert resp.status_code == 404


# --------------------------------------------------------------------------- #
# Presigned URL auth gate


def test_presign_requires_app_token(make_client):
    client, _ = make_client()
    resp = client.post("/uploads/presign", json={"file_name": "doc.pdf", "size_bytes": 4})
    assert resp.status_code == 401


def test_meta_requires_app_token(make_client):
    client, store = make_client()
    resp = client.get("/uploads/some-key/meta")
    assert resp.status_code == 401


# --------------------------------------------------------------------------- #
# resolve() — the upload://<key> → path mapping used by /review & /ask


def test_resolve_returns_path_and_size(make_client):
    from app.uploads import UploadNotFoundError

    client, store = make_client()
    content = b"resolve me"
    presigned = _presign(client, size_bytes=len(content))
    key = _key_from_uri(presigned["upload_uri"])

    client.put(presigned["put_url"], content=content)

    path, size = store.resolve(f"upload://{key}")
    assert size == len(content)
    assert path.read_bytes() == content


def test_resolve_unknown_key_raises_404(make_client):
    from app.uploads import UploadNotFoundError

    client, store = make_client()
    with pytest.raises(UploadNotFoundError):
        store.resolve("upload://no-such-key")


def test_resolve_rejects_non_upload_uri(make_client):
    from app.uploads import UploadError

    client, store = make_client()
    with pytest.raises(UploadError):
        store.resolve("http://example.com/doc")
