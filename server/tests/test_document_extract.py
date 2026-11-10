"""``POST /documents/extract`` contract tests — no network, no pytest run here.

Covers the mobile contract one status code at a time: URL/host/extension guards,
the happy paths for the three formats, the size ceiling, a scanned PDF and an
upstream failure. Every download is served by ``httpx.MockTransport``, so the
suite is offline by construction; the Remote Config read is replaced with a
fixed ceiling for the same reason.
"""

from __future__ import annotations

import io
import zipfile

import fitz
import httpx
import pytest
from fastapi.testclient import TestClient

from app.api import documents
from app.config import Settings, get_settings
from app.main import app

CLOUDINARY_URL = "https://res.cloudinary.com/demo/raw/upload/v1/srs/report.pdf"


@pytest.fixture(autouse=True)
def _offline_remote_config(monkeypatch):
    """Never reach Firebase: the size ceiling is fixed at the documented default."""

    async def _thirty_mb(_settings):
        return 30

    monkeypatch.setattr(documents, "_configured_max_upload_mb", _thirty_mb)
    documents._config_cache = None


@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _serve(monkeypatch, handler):
    """Route every download through a recorder so "no request" is assertable."""
    requests: list[httpx.Request] = []

    def _record(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return handler(request)

    transport = httpx.MockTransport(_record)

    def _client():
        return httpx.AsyncClient(transport=transport, follow_redirects=False, timeout=20.0)

    monkeypatch.setattr(documents, "_client", _client)
    return requests


def _pdf_bytes(*page_texts: str) -> bytes:
    document = fitz.open()
    try:
        for text in page_texts:
            page = document.new_page()
            if text:
                page.insert_text((72, 72), text)
        return document.tobytes()
    finally:
        document.close()


def _docx_bytes() -> bytes:
    xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        "<w:body>"
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        "<w:r><w:t>Giới thiệu</w:t></w:r></w:p>"
        "<w:p><w:r><w:t>Nội dung đoạn văn mô tả hệ thống.</w:t></w:r></w:p>"
        "</w:body></w:document>"
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("word/document.xml", xml)
    return buffer.getvalue()


def _post(client, *, url=CLOUDINARY_URL, file_name="report.pdf"):
    return client.post("/documents/extract", json={"url": url, "file_name": file_name})


# --------------------------------------------------------------------------- #
# Request guards


def test_http_url_is_rejected_with_400(client):
    response = _post(client, url="http://res.cloudinary.com/demo/raw/upload/v1/srs/report.pdf")

    assert response.status_code == 400
    assert isinstance(response.json()["detail"], str)


def test_other_host_is_rejected_and_no_request_is_sent(client, monkeypatch):
    requests = _serve(monkeypatch, lambda request: httpx.Response(200, content=b"# x"))

    response = _post(client, url="https://evil.example.com/demo/raw/upload/v1/srs/report.pdf")

    assert response.status_code == 400
    assert requests == []


def test_exe_extension_is_rejected_with_400(client, monkeypatch):
    requests = _serve(monkeypatch, lambda request: httpx.Response(200, content=b"MZ"))

    response = _post(client, file_name="report.exe")

    assert response.status_code == 400
    assert requests == []


# --------------------------------------------------------------------------- #
# Happy paths


def test_markdown_splits_on_headings(client, monkeypatch):
    body = (
        "# Giới thiệu\nTài liệu mô tả hệ thống.\n## Yêu cầu chức năng\nHệ thống cho phép đăng nhập.\n"
    ).encode()
    _serve(monkeypatch, lambda request: httpx.Response(200, content=body))

    response = _post(client, file_name="report.md")

    assert response.status_code == 200, response.json()
    payload = response.json()
    assert payload["format"] == "md"
    assert payload["page_count"] is None
    assert payload["truncated"] is False
    assert [section["title"] for section in payload["sections"]] == ["Giới thiệu", "Yêu cầu chức năng"]
    assert payload["char_count"] == sum(len(section["text"]) for section in payload["sections"])
    assert payload["char_count"] > 0


def test_pdf_with_two_text_pages_yields_two_page_sections(client, monkeypatch):
    _serve(monkeypatch, lambda request: httpx.Response(200, content=_pdf_bytes("Page one", "Page two")))

    response = _post(client)

    assert response.status_code == 200, response.json()
    payload = response.json()
    assert payload["format"] == "pdf"
    assert payload["page_count"] == 2
    assert len(payload["sections"]) == 2
    assert [section["title"] for section in payload["sections"]] == ["Trang 1", "Trang 2"]
    assert all(section["text"].strip() for section in payload["sections"])
    assert payload["truncated"] is False


def test_docx_heading_starts_a_section(client, monkeypatch):
    _serve(monkeypatch, lambda request: httpx.Response(200, content=_docx_bytes()))

    response = _post(client, file_name="report.docx")

    assert response.status_code == 200, response.json()
    payload = response.json()
    assert payload["format"] == "docx"
    assert payload["page_count"] is None
    assert [section["title"] for section in payload["sections"]] == ["Giới thiệu"]
    assert "Nội dung đoạn văn" in payload["sections"][0]["text"]


# --------------------------------------------------------------------------- #
# Failures


def test_file_over_the_ceiling_is_413(client, monkeypatch):
    async def _one_mb(_settings):
        return 1

    monkeypatch.setattr(documents, "_configured_max_upload_mb", _one_mb)
    _serve(monkeypatch, lambda request: httpx.Response(200, content=b"x" * (1024 * 1024 + 8)))

    response = _post(client)

    assert response.status_code == 413
    assert isinstance(response.json()["detail"], str)


def test_pdf_without_text_is_422(client, monkeypatch):
    _serve(monkeypatch, lambda request: httpx.Response(200, content=_pdf_bytes("")))

    response = _post(client)

    assert response.status_code == 422
    assert isinstance(response.json()["detail"], str)


def test_upstream_404_is_502(client, monkeypatch):
    _serve(monkeypatch, lambda request: httpx.Response(404))

    response = _post(client)

    assert response.status_code == 502
    assert "404" in response.json()["detail"]
