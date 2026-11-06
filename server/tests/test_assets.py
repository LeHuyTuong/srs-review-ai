"""Cloudinary intent/finalize + Firestore index — no network, no credentials.

The real ``CloudinaryClient`` signs everything (so the HMAC and Cloudinary
signature paths run for real); only ``fetch`` — the Admin API call — is
replaced by an in-memory "what Cloudinary holds" map, and Firestore by
``InMemoryReportIndex``.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import Settings, get_settings
from app.infrastructure.cloudinary_assets import (
    CloudinaryClient,
    CloudinaryUnavailableError,
    IntentExpiredError,
    IntentTokenError,
    StoredResource,
    sign_params,
)
from app.infrastructure.report_index import InMemoryReportIndex, ReportIndexError
from app.main import app

APP_TOKEN = "test-app-secret"
HEADERS = {"X-App-Token": APP_TOKEN}

# Hợp đồng Firestore mà row server ghi ra phải khớp (ADR-0020).
CONTRACTS_DIR = Path(__file__).resolve().parents[2] / "contracts" / "firestore"


def _assert_row_matches_assets_contract(row: dict) -> None:
    """Row server ghi phải khớp contracts/firestore/assets.schema.json.

    Không dùng jsonschema (repo không thêm dependency): chỉ kiểm đúng những điều
    hợp đồng đang khoá — key nằm trong properties, required đủ mặt, source
    thuộc enum, provider đúng const, và fileSize không nhỏ hơn trần.
    """

    schema = json.loads((CONTRACTS_DIR / "assets.schema.json").read_text(encoding="utf-8"))
    properties = schema["properties"]
    extra = sorted(set(row) - set(properties))
    assert not extra, f"row có key ngoài hợp đồng: {extra}"
    missing = sorted(set(schema["required"]) - set(row))
    assert not missing, f"row thiếu field bắt buộc: {missing}"
    assert row["source"] in properties["source"]["enum"]
    assert row["provider"] == properties["provider"]["const"]
    assert row["fileSize"] >= properties["fileSize"]["minimum"]


class FakeCloudinary(CloudinaryClient):
    def __init__(self, **kwargs) -> None:
        super().__init__(**{"cloud_name": "demo", "api_key": "k123", "api_secret": "s3cret", **kwargs})
        self.stored: dict[str, StoredResource] = {}
        self.unavailable = False

    def put(self, public_id: str, size: int) -> None:
        self.stored[public_id] = StoredResource(
            public_id=public_id,
            bytes=size,
            secure_url=f"https://res.cloudinary.com/demo/raw/upload/v1/{public_id}",
            resource_type="raw",
        )

    def fetch(self, public_id: str) -> StoredResource | None:
        if self.unavailable:
            raise CloudinaryUnavailableError("boom")
        return self.stored.get(public_id)


class FailingIndex:
    def record(self, doc_id, data):
        raise ReportIndexError("Firestore write failed: DefaultCredentialsError")


@pytest.fixture
def env(monkeypatch):
    host = FakeCloudinary()
    index = InMemoryReportIndex()
    monkeypatch.setattr(main_module, "_asset_host", host)
    monkeypatch.setattr(main_module, "_report_index", index)
    settings = Settings(mock_mode=True, gemini_api_key="", app_token=APP_TOKEN)
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        yield TestClient(app), host, index, monkeypatch
    finally:
        app.dependency_overrides.pop(get_settings, None)


def _intent(client, **overrides):
    body = {"file_name": "OTES SRS.pdf", "size_bytes": 1234, "source": "desktop", "uploaded_by": "u-1"}
    body.update(overrides)
    return client.post("/assets/upload-intents", json=body, headers=HEADERS)


def _finalize(client, intent, token=None, asset_id=None):
    return client.post(
        f"/assets/{asset_id or intent['asset_id']}/finalize",
        json={"intent_token": token or intent["intent_token"]},
        headers=HEADERS,
    )


def test_sign_params_matches_cloudinary_documented_example():
    # Example from Cloudinary's "Generating authentication signatures" docs.
    params = {
        "eager": "w_400,h_300,c_pad|w_260,h_200,c_crop",
        "public_id": "sample_image",
        "timestamp": "1315060510",
    }
    assert sign_params(params, "abcd") == "bfd09f95f331f558cbd1320e67aa8d488770583e"


def test_sign_params_ignores_unsigned_fields():
    base = {"public_id": "a", "timestamp": "1"}
    noisy = {**base, "api_key": "x", "file": "f", "resource_type": "raw"}
    assert sign_params(noisy, "s") == sign_params(base, "s")


def test_intent_returns_signed_form_and_public_id_under_folder(env):
    client, host, _, _ = env
    response = _intent(client)
    assert response.status_code == 201
    body = response.json()
    fields = body["fields"]
    assert body["upload_url"] == "https://api.cloudinary.com/v1_1/demo/raw/upload"
    assert fields["public_id"] == f"srs_reports/{body['asset_id']}/OTES_SRS.pdf"
    assert fields["api_key"] == "k123"
    signed = {"public_id": fields["public_id"], "timestamp": fields["timestamp"]}
    assert fields["signature"] == sign_params(signed, "s3cret")
    assert "s3cret" not in response.text


def test_intent_requires_app_token(env):
    client, *_ = env
    body = {"file_name": "a.pdf", "size_bytes": 1, "source": "desktop"}
    response = client.post("/assets/upload-intents", json=body)
    assert response.status_code == 401


def test_intent_rejects_over_free_plan_size(env):
    client, *_ = env
    response = _intent(client, size_bytes=10 * 1024 * 1024 + 1)
    assert response.status_code == 413
    assert "10 MB" in response.json()["detail"]


def test_intent_rejects_other_extensions(env):
    client, *_ = env
    assert _intent(client, file_name="notes.exe").status_code == 422


def test_intent_503_when_cloudinary_not_configured(env):
    client, _, _, monkeypatch = env
    unconfigured = CloudinaryClient(cloud_name="", api_key="", api_secret="")
    monkeypatch.setattr(main_module, "_asset_host", unconfigured)
    assert _intent(client).status_code == 503


def test_finalize_records_verified_row_in_firestore(env):
    client, host, index, _ = env
    intent = _intent(client, uploaded_by_email="sv@fpt.edu.vn", owner_uid="uid-9", source="mobile").json()
    host.put(intent["fields"]["public_id"], 1234)

    response = _finalize(client, intent)

    assert response.status_code == 200
    row = index.rows[intent["asset_id"]]
    assert row["fileName"] == "OTES SRS.pdf"
    assert row["fileSize"] == 1234
    assert row["source"] == "mobile"
    assert row["uploadedByEmail"] == "sv@fpt.edu.vn"
    assert row["ownerUid"] == "uid-9"
    assert row["provider"] == "cloudinary"
    assert row["storagePath"] == intent["fields"]["public_id"]
    assert row["downloadUrl"].startswith("https://res.cloudinary.com/demo/raw/upload/")
    assert row["uploadedAt"] == "SERVER_TIMESTAMP"


def test_finalize_row_matches_assets_contract_with_email_and_owner(env):
    client, host, index, _ = env
    intent = _intent(client, uploaded_by_email="sv@fpt.edu.vn", owner_uid="uid-9", source="mobile").json()
    host.put(intent["fields"]["public_id"], 1234)

    assert _finalize(client, intent).status_code == 200

    _assert_row_matches_assets_contract(index.rows[intent["asset_id"]])


def test_finalize_row_matches_assets_contract_without_email_and_owner(env):
    client, host, index, _ = env
    intent = _intent(client, uploaded_by="u-1", source="desktop").json()
    host.put(intent["fields"]["public_id"], 1234)

    assert _finalize(client, intent).status_code == 200

    row = index.rows[intent["asset_id"]]
    _assert_row_matches_assets_contract(row)
    # Không có email/owner thì server BỎ field, không ghi null.
    assert "uploadedByEmail" not in row
    assert "ownerUid" not in row
    assert row["uploadedBy"] == "u-1"


def test_finalize_row_allows_empty_uploader_label(env):
    client, host, index, _ = env
    intent = _intent(client, uploaded_by="", uploaded_by_email="", owner_uid="").json()
    host.put(intent["fields"]["public_id"], 1234)

    assert _finalize(client, intent).status_code == 200

    row = index.rows[intent["asset_id"]]
    _assert_row_matches_assets_contract(row)
    # Cả ba claims rỗng thì uploadedBy là chuỗi rỗng, không phải null.
    assert row["uploadedBy"] == ""


def test_finalize_twice_rewrites_same_document(env):
    client, host, index, _ = env
    intent = _intent(client).json()
    host.put(intent["fields"]["public_id"], 1234)
    for _ in range(2):
        response = _finalize(client, intent)
        assert response.status_code == 200
    assert list(index.rows) == [intent["asset_id"]]


def test_finalize_409_before_upload_lands(env):
    client, _, index, _ = env
    intent = _intent(client).json()
    response = _finalize(client, intent)
    assert response.status_code == 409
    assert index.rows == {}


def test_finalize_rejects_size_mismatch(env):
    client, host, index, _ = env
    intent = _intent(client).json()
    host.put(intent["fields"]["public_id"], 999)
    response = _finalize(client, intent)
    assert response.status_code == 422
    assert index.rows == {}


def test_finalize_rejects_tampered_token_and_foreign_asset(env):
    client, host, _, _ = env
    intent = _intent(client).json()
    host.put(intent["fields"]["public_id"], 1234)
    tampered = intent["intent_token"][:-2] + ("AA" if not intent["intent_token"].endswith("AA") else "BB")
    bad = _finalize(client, intent, token=tampered)
    assert bad.status_code == 400
    other = _finalize(client, intent, asset_id="deadbeef")
    assert other.status_code == 400


def test_finalize_502_when_firestore_write_fails_and_retry_is_possible(env):
    client, host, _, monkeypatch = env
    intent = _intent(client).json()
    host.put(intent["fields"]["public_id"], 1234)
    monkeypatch.setattr(main_module, "_report_index", FailingIndex())
    response = _finalize(client, intent)
    assert response.status_code == 502


def test_finalize_503_when_cloudinary_admin_api_down(env):
    client, host, _, _ = env
    intent = _intent(client).json()
    host.unavailable = True
    response = _finalize(client, intent)
    assert response.status_code == 503


def test_intent_token_expiry_and_signature():
    host = FakeCloudinary()
    token = host.sign_intent({"aid": "a", "exp": 100})
    assert host.verify_intent(token, now=50)["aid"] == "a"
    with pytest.raises(IntentExpiredError):
        host.verify_intent(token, now=101)
    with pytest.raises(IntentTokenError):
        FakeCloudinary(api_secret="other").verify_intent(token, now=50)
    with pytest.raises(IntentTokenError):
        host.verify_intent("not-a-token", now=50)
