"""Plain-text extraction for a submitted SRS file (PDF / DOCX / Markdown).

The mobile client uploads the student's file to Cloudinary and then sends the
URL here, so the AI review reads the *real* document instead of the demo text.
This module is framework-free: it takes bytes + a format and returns sections —
no HTTP, no FastAPI, no settings.

Section policy
==============
* PDF: the document's own bookmarks (TOC) when it has them; otherwise one
  section per page, titled ``Trang N``. A file with no extractable text (a scan
  saved as images) yields no sections — the route turns that into a 422.
* DOCX: paragraphs of ``word/document.xml`` grouped under the nearest Heading /
  ``Tiêu đề`` style paragraph.
* Markdown: lines starting with ``#`` open a section.

Empty sections are dropped, and the total body text is capped at
``MAX_CHARS`` so one huge document cannot be shipped into a prompt.
"""

from __future__ import annotations

import io
import zipfile
from xml.etree import ElementTree as ET

import fitz  # PyMuPDF

MAX_CHARS = 60_000
"""Total body-text ceiling across every section; the route reports ``truncated``."""

_DOCX_XML_MAX_BYTES = 50 * 1024 * 1024
"""Uncompressed ``word/document.xml`` ceiling (zip-bomb guard)."""

SUPPORTED_FORMATS = ("pdf", "docx", "md")

_W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
_W_P = f"{_W_NS}p"
_W_PPR = f"{_W_NS}pPr"
_W_PSTYLE = f"{_W_NS}pStyle"
_W_T = f"{_W_NS}t"
_W_BR = f"{_W_NS}br"
_W_TAB = f"{_W_NS}tab"

_PREAMBLE_TITLE = "Mở đầu"


class ExtractedSections(list):
    """``list[dict[str, str]]`` plus the truncation verdict.

    The public contract is the ``(sections, page_count)`` tuple. The extra
    attribute keeps callers from guessing "was anything cut" from a length that
    is also 60 000 when the document is exactly full.
    """

    def __init__(self, sections: list[dict[str, str]] | None = None, *, truncated: bool = False) -> None:
        super().__init__(sections or [])
        self.truncated = truncated


def extract(data: bytes, fmt: str) -> tuple[ExtractedSections, int | None]:
    """Extract sectioned text from ``data``.

    Returns ``(sections, page_count)``; ``page_count`` is ``None`` for DOCX and
    Markdown, which have no page model in the bytes we receive. Sections are
    ``{"title": str, "text": str}`` and already capped at :data:`MAX_CHARS`.
    Raises ``ValueError`` for an unsupported format or unreadable bytes.
    """
    normalised = (fmt or "").strip().lower()
    if normalised == "pdf":
        raw, page_count = _extract_pdf(data)
    elif normalised == "docx":
        raw, page_count = _extract_docx(data), None
    elif normalised == "md":
        raw, page_count = _extract_md(data), None
    else:
        raise ValueError(f"unsupported document format: {fmt!r}")
    return _capped(raw), page_count


# --------------------------------------------------------------------------- #
# Shared shaping


def _capped(raw: list[tuple[str, str]]) -> ExtractedSections:
    """Drop empty sections, then enforce the global character ceiling."""
    sections: list[dict[str, str]] = []
    for title, text in raw:
        body = text.strip()
        if not body:
            continue
        sections.append({"title": (title or _PREAMBLE_TITLE).strip() or _PREAMBLE_TITLE, "text": body})

    total = sum(len(section["text"]) for section in sections)
    if total <= MAX_CHARS:
        return ExtractedSections(sections)

    remaining = MAX_CHARS
    kept: list[dict[str, str]] = []
    for section in sections:
        if remaining <= 0:
            break
        body = section["text"][:remaining]
        if body.strip():
            kept.append({"title": section["title"], "text": body})
        remaining -= len(body)
    return ExtractedSections(kept, truncated=True)


# --------------------------------------------------------------------------- #
# PDF


def _extract_pdf(data: bytes) -> tuple[list[tuple[str, str]], int]:
    with fitz.open(stream=data, filetype="pdf") as doc:
        page_count = doc.page_count
        page_texts = [doc.load_page(index).get_text("text") for index in range(page_count)]
        toc = doc.get_toc(simple=True)

    if not toc:
        return [(f"Trang {index + 1}", text) for index, text in enumerate(page_texts)], page_count

    entries: list[tuple[str, int]] = []
    for item in toc:
        if len(item) < 3:
            continue
        page_number = int(item[2] or 0)
        if page_number < 1:
            continue
        entries.append((str(item[1] or "").strip(), min(page_number, page_count)))
    if not entries:
        return [(f"Trang {index + 1}", text) for index, text in enumerate(page_texts)], page_count

    raw: list[tuple[str, str]] = []
    covered_until = 0
    for position, (title, start_page) in enumerate(entries):
        start = start_page - 1
        # Text before the first bookmark has no section of its own; keep it as
        # per-page sections rather than silently losing the cover page.
        for page_index in range(covered_until, start):
            raw.append((f"Trang {page_index + 1}", page_texts[page_index]))

        end = entries[position + 1][1] - 1 if position + 1 < len(entries) else page_count
        if end <= start:
            # Several bookmarks can point at one page; the later (deeper) entry
            # owns that page, so this one has no body of its own.
            continue
        raw.append((title, "\n".join(page_texts[start:end])))
        covered_until = max(covered_until, end)

    # A bookmark may start past the end of the file; keep the tail readable.
    for page_index in range(covered_until, page_count):
        raw.append((f"Trang {page_index + 1}", page_texts[page_index]))
    return raw, page_count


# --------------------------------------------------------------------------- #
# DOCX


def _extract_docx(data: bytes) -> list[tuple[str, str]]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        # Uncompressed size comes from the archive header: refuse a zip bomb
        # before inflating it rather than after it has filled memory.
        if archive.getinfo("word/document.xml").file_size > _DOCX_XML_MAX_BYTES:
            raise ValueError("DOCX document.xml is larger than the extraction ceiling")
        document = archive.read("word/document.xml")
    # A submitted DOCX is untrusted input. Python's ElementTree resolves
    # internal entities, so malformed/entity-expanding XML is refused before
    # it is parsed instead of relying on parser memory limits.
    upper = document.upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        raise ValueError("DOCX document.xml must not declare a DOCTYPE or ENTITY")
    root = ET.fromstring(document)  # noqa: S314 - DOCTYPE/ENTITY rejected above

    sections: list[tuple[str, str]] = []
    title = _PREAMBLE_TITLE
    buffer: list[str] = []

    def flush() -> None:
        sections.append((title, "\n".join(buffer)))
        buffer.clear()

    for paragraph in root.iter(_W_P):
        heading = _docx_heading(paragraph)
        if heading is not None:
            flush()
            title = heading or _PREAMBLE_TITLE
            continue
        text = _docx_paragraph_text(paragraph)
        if text:
            buffer.append(text)
    flush()
    return sections


def _docx_heading(paragraph: ET.Element) -> str | None:
    """The heading text when this paragraph carries a Heading/Tiêu đề style."""
    properties = paragraph.find(_W_PPR)
    if properties is None:
        return None
    style = properties.find(_W_PSTYLE)
    if style is None:
        return None
    style_id = (style.get(f"{_W_NS}val") or "").strip().lower()
    if not (
        style_id.startswith("heading") or style_id.startswith("tiêu đề") or style_id.startswith("tieu de")
    ):
        return None
    return _docx_paragraph_text(paragraph)


def _docx_paragraph_text(paragraph: ET.Element) -> str:
    parts: list[str] = []
    for node in paragraph.iter():
        if node.tag == _W_T and node.text:
            parts.append(node.text)
        elif node.tag == _W_BR:
            parts.append("\n")
        elif node.tag == _W_TAB:
            parts.append("\t")
    return "".join(parts).strip()


# --------------------------------------------------------------------------- #
# Markdown


def _extract_md(data: bytes) -> list[tuple[str, str]]:
    text = data.decode("utf-8", errors="replace")
    sections: list[tuple[str, str]] = []
    title = _PREAMBLE_TITLE
    buffer: list[str] = []

    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            sections.append((title, "\n".join(buffer)))
            buffer.clear()
            title = line.strip().lstrip("#").strip() or _PREAMBLE_TITLE
            continue
        buffer.append(line)
    sections.append((title, "\n".join(buffer)))
    return sections
