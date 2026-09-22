"""Document-anatomy extraction (docmap.py) + /documents endpoints.

Fixture PDFs are built in-memory with PyMuPDF itself — no binary fixtures in
git, and the same library writes and reads so the tests pin BEHAVIOUR
(image bbox, vector clusters, TOC spans, mxfile decode), not library quirks.
"""

from __future__ import annotations

import base64
import struct
import zlib
from pathlib import Path

import fitz
import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app import docmap
from app.config import Settings, get_settings
from app.main import app
from app.uploads import UploadStore

APP_TOKEN = "test-app-secret"


# --------------------------------------------------------------------- #
# Fixture builders
# --------------------------------------------------------------------- #
def _png_chunk(typ: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data))


def make_mxfile_png(mxfile_xml: str = "<mxfile><diagram id='d1'/></mxfile>") -> bytes:
    """A valid 1×1 PNG carrying a draw.io ``mxfile`` tEXt chunk."""
    payload = base64.b64encode(zlib.compress(mxfile_xml.encode())[2:-4])
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\x00\x00\x00")
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"tEXt", b"mxfile\x00" + payload)
        + _png_chunk(b"IDAT", idat)
        + _png_chunk(b"IEND", b"")
    )


def make_plain_png() -> bytes:
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\xff\x00\x00")
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", idat)
        + _png_chunk(b"IEND", b"")
    )


def make_pdf(
    path: Path,
    *,
    with_toc: bool = True,
    with_image: bool = True,
    with_drawings: bool = True,
    mxfile: bool = False,
) -> Path:
    doc = fitz.open()
    page1 = doc.new_page()  # ~595×842 pt
    page1.insert_text((72, 72), "1. Introduction")
    page1.insert_text((72, 100), "This section is prose. " * 20)

    page2 = doc.new_page()
    page2.insert_text((72, 72), "2. Design")
    if with_image:
        png = make_mxfile_png() if mxfile else make_plain_png()
        page2.insert_image(fitz.Rect(72, 120, 312, 360), stream=png)
    if with_drawings:
        # A fake UML-ish cluster: 8 boxes + lines in the lower half.
        for i in range(8):
            x = 72 + (i % 4) * 60
            y = 450 + (i // 4) * 80
            page2.draw_rect(fitz.Rect(x, y, x + 50, y + 40))
        for i in range(4):
            page2.draw_line(fitz.Point(100 + i * 60, 490), fitz.Point(100 + i * 60, 530))
        # Decoration that must NOT become a region: one short line.
        page2.draw_line(fitz.Point(72, 830), fitz.Point(300, 830))
    page3 = doc.new_page()
    page3.draw_rect(fitz.Rect(0, 0, 595, 842))  # page-border frame → filtered
    for i in range(10):  # dense cluster INSIDE the frame
        page3.draw_rect(fitz.Rect(100 + i * 5, 100 + i * 5, 300, 400))
    if with_toc:
        doc.set_toc(
            [
                [1, "1. Introduction", 1],
                [1, "2. Design", 2],
                [2, "2.1 Database Design", 3],
            ]
        )
    doc.save(path)
    doc.close()
    return path


# --------------------------------------------------------------------- #
# analyze_document
# --------------------------------------------------------------------- #
def test_analyze_finds_image_with_bbox_and_section_spans(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf")
    result = docmap.analyze_document(pdf)

    assert result.toc_source == "bookmarks"
    intro = next(s for s in result.sections if s.title.startswith("1."))
    design = next(s for s in result.sections if s.title == "2. Design")
    assert intro.start_page == 0 and intro.end_page == 0
    assert design.start_page == 1 and design.end_page == 2  # until next L1

    page2 = result.pages[1]
    images = [f for f in page2.figures if f.kind == "image"]
    assert len(images) == 1
    assert images[0].bbox == pytest.approx((72, 120, 312, 360), abs=0.1)
    assert images[0].xref is not None
    assert images[0].pixel_width == 1


def test_analyze_clusters_vector_drawings_and_filters_noise(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf", with_image=False)
    result = docmap.analyze_document(pdf)

    page2 = result.pages[1]
    drawings = [f for f in page2.figures if f.kind == "drawing"]
    assert len(drawings) == 1  # 12 paths merge into ONE region
    box = drawings[0].bbox
    assert box[0] <= 72 and box[1] <= 450  # covers the UML-ish cluster
    assert drawings[0].drawing_items >= 12
    # The single footer line is decoration, not a figure:
    assert all(f.bbox[1] < 830 for f in page2.figures)

    page3 = result.pages[2]
    # The full-page border frame is dropped; the inner dense cluster survives.
    assert all(abs(f.bbox[2] - 595) > 1 or abs(f.bbox[3] - 842) > 1 for f in page3.figures)
    assert any(f.kind == "drawing" for f in page3.figures)


def test_scan_embedded_decodes_drawio_mxfile_from_png_bytes():
    """PDF image XObjects store raw samples (PNG ancillary chunks are destroyed
    by every producer), so mxfile decode is exercised at the BYTES level — this
    is the path the DOCX-media pipeline will use, where the PNG file survives."""
    xml, truncated, readable = docmap._scan_embedded(make_mxfile_png(), "png")
    assert readable == "mxfile"
    assert not truncated
    assert xml is not None and "<diagram id='d1'/>" in xml


def test_scan_embedded_marks_plain_png_and_text_svg():
    assert docmap._scan_embedded(make_plain_png(), "png") == (None, False, "vision-required")
    svg = ("<svg>" + "<text>x</text>" * 10 + "</svg>").encode()
    assert docmap._scan_embedded(svg, "svg") == (None, False, "svg-text")
    raster_svg = ("<svg>" + "<image href='x'/>" * 10 + "</svg>").encode()
    assert docmap._scan_embedded(raster_svg, "svg") == (None, False, "vision-required")


def test_analyze_marks_plain_png_as_vision_required(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf", with_drawings=False, mxfile=False)
    result = docmap.analyze_document(pdf)
    image = next(f for f in result.pages[1].figures if f.kind == "image")
    assert image.readable == "vision-required"
    assert image.embedded_xml is None


def test_analyze_heading_fallback_when_no_bookmarks(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf", with_toc=False, with_image=False, with_drawings=False)
    result = docmap.analyze_document(pdf)
    assert result.toc_source == "headings"
    titles = [s.title for s in result.sections]
    assert any(t.startswith("1. Introduction") for t in titles)
    assert any(t.startswith("2. Design") for t in titles)


def test_analyze_text_only_document_reports_no_figures(tmp_path: Path):
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((72, 72), "Plain prose only. " * 40)
    doc.save(tmp_path / "plain.pdf")
    doc.close()
    result = docmap.analyze_document(tmp_path / "plain.pdf")
    assert result.toc_source == "none"
    assert all(not p.figures for p in result.pages)


# --------------------------------------------------------------------- #
# render_region_png
# --------------------------------------------------------------------- #
def test_render_full_page_and_bbox_crop(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf")
    full = docmap.render_region_png(pdf, page_index=1)
    crop = docmap.render_region_png(pdf, page_index=1, bbox=(72, 120, 312, 360), scale=3.0)
    assert full.startswith(b"\x89PNG") and crop.startswith(b"\x89PNG")
    assert len(crop) < len(full)  # tight crop, not a downscaled page


def test_render_rejects_out_of_range_page_and_empty_bbox(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf")
    with pytest.raises(ValueError, match="out of range"):
        docmap.render_region_png(pdf, page_index=99)
    with pytest.raises(ValueError, match="intersect"):
        docmap.render_region_png(pdf, page_index=0, bbox=(5000, 5000, 5100, 5100))


def test_render_scale_is_capped_to_max_side(tmp_path: Path):
    pdf = make_pdf(tmp_path / "doc.pdf")
    png = docmap.render_region_png(pdf, page_index=0, scale=6.0, max_side_px=600)
    pix = fitz.Pixmap(png)
    assert max(pix.width, pix.height) <= 600


# --------------------------------------------------------------------- #
# /documents endpoints (upload-store backed, like test_uploads.py)
# --------------------------------------------------------------------- #
@pytest.fixture
def make_client(tmp_path: Path, monkeypatch):
    def _make():
        store = UploadStore(upload_dir=tmp_path / "uploads", max_bytes=40 * 1024 * 1024, secret=APP_TOKEN)
        monkeypatch.setattr(main_module, "_upload_store", store)
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=True, gemini_api_key="", app_token=APP_TOKEN
        )
        return TestClient(app), store

    yield _make
    app.dependency_overrides.clear()


def _upload_pdf(client: TestClient, pdf_path: Path) -> str:
    data = pdf_path.read_bytes()
    resp = client.post(
        "/uploads/presign",
        json={"file_name": "doc.pdf", "size_bytes": len(data)},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert resp.status_code == 200, resp.text
    put = client.put(resp.json()["put_url"], content=data)
    assert put.status_code == 201, put.text
    return f"upload://{put.json()['key']}"


def test_analyze_endpoint_roundtrip_and_disk_cache(make_client, tmp_path: Path):
    client, _ = make_client()
    uri = _upload_pdf(client, make_pdf(tmp_path / "doc.pdf"))
    headers = {"X-App-Token": APP_TOKEN}

    resp = client.post("/documents/analyze", json={"uri": uri}, headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["page_count"] == 3
    assert body["toc_source"] == "bookmarks"
    assert body["pages"][1]["figures"], "page 2 must report its image + drawing cluster"

    resp2 = client.post("/documents/analyze", json={"uri": uri}, headers=headers)
    assert resp2.status_code == 200
    assert resp2.json() == body  # sidecar cache hit, byte-identical


def test_analyze_endpoint_rejects_unknown_and_garbage(make_client, tmp_path: Path):
    client, store = make_client()
    headers = {"X-App-Token": APP_TOKEN}

    resp = client.post("/documents/analyze", json={"uri": "upload://nope"}, headers=headers)
    assert resp.status_code == 404

    garbage = tmp_path / "garbage.pdf"
    garbage.write_bytes(b"this is not a pdf at all")
    uri = _upload_pdf(client, garbage)
    resp = client.post("/documents/analyze", json={"uri": uri}, headers=headers)
    assert resp.status_code == 422


def test_render_endpoint_returns_png_and_caches(make_client, tmp_path: Path):
    client, _ = make_client()
    uri = _upload_pdf(client, make_pdf(tmp_path / "doc.pdf"))
    headers = {"X-App-Token": APP_TOKEN}

    analyze = client.post("/documents/analyze", json={"uri": uri}, headers=headers).json()
    figure = next(f for f in analyze["pages"][1]["figures"] if f["kind"] == "image")

    payload = {"uri": uri, "page_index": 1, "bbox": list(figure["bbox"]), "scale": 3.0}
    resp = client.post("/documents/render", json=payload, headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"] == "image/png"
    assert resp.content.startswith(b"\x89PNG")

    resp2 = client.post("/documents/render", json=payload, headers=headers)
    assert resp2.content == resp.content  # render cache hit


def test_render_endpoint_validates_page(make_client, tmp_path: Path):
    client, _ = make_client()
    uri = _upload_pdf(client, make_pdf(tmp_path / "doc.pdf"))
    resp = client.post(
        "/documents/render",
        json={"uri": uri, "page_index": 99},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert resp.status_code == 422


def test_documents_endpoints_require_app_token_when_set(make_client, tmp_path: Path):
    client, _ = make_client()
    uri = _upload_pdf(client, make_pdf(tmp_path / "doc.pdf"))
    assert client.post("/documents/analyze", json={"uri": uri}).status_code == 401
    assert client.post("/documents/render", json={"uri": uri, "page_index": 0}).status_code == 401
