"""Document anatomy extraction — the server's eyes (sds-reviewer step 1, EXTRACT).

Why this exists
===============
The Flutter client parses PDFs with syncfusion_flutter_pdf, which exposes text
extraction ONLY. Its ``imagePageIndexes`` were therefore a text-density guess
("page has < 120 chars → probably holds a figure") that missed every
vector-drawn diagram — and Word-exported UML (sequence/class/ERD) is vector,
not embedded raster. The result: diagram sections were reviewed blind and
scored 0/10 with "add the actual diagrams".

PyMuPDF sees the real objects:

* ``page.get_images(full=True)`` + ``page.get_image_rects(xref)``
      → embedded raster images WITH their bounding boxes on the page.
* ``page.get_drawings()``  → vector path clusters = diagrams Word exported as
      drawings (the OTES case). Clustered into regions so one class diagram is
      one region, not 400 separate lines.
* ``doc.get_toc()``        → the document's own bookmarks → real section spans
      (heading → page range), replacing the client's regex-split guesswork.
* PNG ``mxfile`` chunks    → draw.io source XML embedded in the raster
      (sds-reviewer INVENTORY step: decodable source beats vision 100%).
      NOTE: PDF image XObjects store RAW SAMPLES, not the original PNG file —
      ancillary chunks (mxfile) are destroyed by every PDF producer. The
      scanner stays in place for the DOCX-media pipeline, where ``word/media/*``
      keeps the original file untouched.

Output contract
===============
``analyze_document(path)`` returns a :class:`DocumentMap` — sections, and per
page a list of figure regions with bounding boxes. ``render_region_png``
rasterises exactly one region at high DPI so the vision model reads a tight
crop (sds-reviewer CROP step: reading a whole 1780×2048 page in one shot
measurably drops findings).

The module is framework-free: FastAPI routes live in ``main.py``; swap the
UploadStore backend and this file does not change.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import struct
import zlib
from pathlib import Path
from typing import Literal

import fitz  # PyMuPDF
from pydantic import BaseModel, Field

DOCMAP_VERSION = "1"
"""Bump when the extraction logic changes; invalidates analyze sidecar caches."""

MXFILE_CHAR_CAP = 60_000
"""A decoded draw.io source can be huge; cap it so the map stays cheap to ship."""

# --------------------------------------------------------------------- #
# Vector-clustering heuristics (tuned on Word-exported UML pages)
# --------------------------------------------------------------------- #
_CLUSTER_GAP_PT = 18.0
"""Two drawing paths closer than this many points belong to the same diagram."""

_MIN_DRAWING_ITEMS = 6
"""Fewer paths than this is decoration (a rule line, a bullet), not a diagram."""

_MIN_REGION_SIDE_PT = 48.0
"""A diagram region must be at least this wide AND tall (points)."""

_PAGE_FRAME_COVERAGE = 0.95
"""A cluster covering ≥95% of the page is a page border frame, not a figure."""

_HEADING_RE = re.compile(r"^\s*(\d+(?:\.\d+)*)([.)]?)\s+(\S.{2,96})$")
"""Numbered-heading fallback when the PDF has no bookmarks (``toc_source="headings"``)."""


class FigureRegion(BaseModel):
    """One diagram-ish region on one page — a placed image or a vector cluster."""

    model_config = {"extra": "forbid"}

    kind: Literal["image", "drawing"]
    bbox: tuple[float, float, float, float]
    """``(x0, y0, x1, y1)`` in PDF points, origin top-left (PyMuPDF space)."""
    xref: int | None = None
    """Image object number (``kind="image"`` only) — for dedup across pages."""
    pixel_width: int | None = None
    pixel_height: int | None = None
    drawing_items: int | None = None
    """Path count inside a ``kind="drawing"`` cluster — a complexity signal."""
    embedded_xml: str | None = None
    """Decoded draw.io ``mxfile`` source, when the raster carries one. When set,
    the diagram is machine-readable WITHOUT a vision model (best accuracy)."""
    embedded_xml_truncated: bool = False
    readable: Literal["mxfile", "svg-text", "vision-required"] = "vision-required"
    """sds-reviewer INVENTORY verdict: mxfile/SVG text beat the vision model;
    anything else MUST go through a vision pass to be read at all."""


class PageAnatomy(BaseModel):
    model_config = {"extra": "forbid"}

    index: int
    """0-based page number, matching the client's ``pageIndex`` convention."""
    text_length: int
    figures: list[FigureRegion] = Field(default_factory=list)


class SectionSpan(BaseModel):
    model_config = {"extra": "forbid"}

    title: str
    level: int
    start_page: int
    end_page: int
    """Inclusive, 0-based."""


class DocumentMap(BaseModel):
    model_config = {"extra": "forbid"}

    version: str = DOCMAP_VERSION
    page_count: int
    toc_source: Literal["bookmarks", "headings", "none"]
    sections: list[SectionSpan] = Field(default_factory=list)
    pages: list[PageAnatomy] = Field(default_factory=list)


# --------------------------------------------------------------------- #
# Embedded-source scan — bytes-based port of sds-reviewer/scan_embedded_xml.py
# --------------------------------------------------------------------- #
def _png_mxfile(data: bytes) -> str | None:
    """Decode the draw.io ``mxfile`` chunk from PNG bytes, if present."""
    if not data.startswith(b"\x89PNG"):
        return None
    i = 8
    while i < len(data) - 8:
        (ln,) = struct.unpack(">I", data[i : i + 4])
        typ = data[i + 4 : i + 8]
        if typ in (b"tEXt", b"iTXt", b"zTXt"):
            key, _, rest = data[i + 8 : i + 8 + ln].partition(b"\x00")
            if key == b"mxfile":
                try:
                    return zlib.decompress(base64.b64decode(rest), -15).decode("utf-8", "replace")
                except Exception:  # corrupt chunk — treat as unreadable, not fatal
                    return None
        if typ == b"IEND":
            break
        i += 12 + ln
    return None


def _svg_textable(data: bytes) -> bool:
    """True when an SVG carries real ``<text>`` nodes (grep-able labels)."""
    head = data[:400_000].decode("utf-8", "ignore")
    return len(re.findall(r"<text", head)) > 5


def _scan_embedded(image_bytes: bytes, ext: str) -> tuple[str | None, bool, str]:
    """Return ``(embedded_xml, truncated, readable)`` for one image blob."""
    if ext == "png":
        xml = _png_mxfile(image_bytes)
        if xml is None:
            return None, False, "vision-required"
        truncated = len(xml) > MXFILE_CHAR_CAP
        return xml[:MXFILE_CHAR_CAP], truncated, "mxfile"
    if ext == "svg":
        return None, False, "svg-text" if _svg_textable(image_bytes) else "vision-required"
    return None, False, "vision-required"


# --------------------------------------------------------------------- #
# Vector-drawing clustering
# --------------------------------------------------------------------- #
def _union(a: fitz.Rect, b: fitz.Rect) -> fitz.Rect:
    return fitz.Rect(min(a.x0, b.x0), min(a.y0, b.y0), max(a.x1, b.x1), max(a.y1, b.y1))


def _union_all(rects: list[fitz.Rect]) -> fitz.Rect:
    box = fitz.Rect(rects[0])
    for rect in rects[1:]:
        box = _union(box, rect)
    return box


def _cluster_drawings(page: fitz.Page) -> list[FigureRegion]:
    """Group a page's vector paths into diagram regions.

    Word exports UML as hundreds of small paths; a greedy expanding-box merge
    (paths within ``_CLUSTER_GAP_PT`` join one cluster) turns them back into
    "one diagram = one bbox". Decoration is filtered out by item count and
    minimum size; page-border frames are dropped by coverage.
    """
    drawings = page.get_drawings()
    if not drawings:
        return []

    rects: list[fitz.Rect] = []
    page_area = abs(page.rect) or 1.0
    for d in drawings:
        rect = fitz.Rect(d["rect"])
        if rect.is_infinite:
            continue
        # A connector LINE has a zero-width (or zero-height) bounding rect,
        # which fitz reports as "empty" — but connectors are precisely what
        # hold a diagram's boxes together, so inflate them to 1 pt instead
        # of dropping them.
        if rect.width <= 0:
            rect.x1 = rect.x0 + 1
        if rect.height <= 0:
            rect.y1 = rect.y0 + 1
        # Drop page-border frames BEFORE clustering: a frame contains every
        # content rect, so it would swallow the whole page into one cluster
        # that the post-merge coverage filter then deletes wholesale.
        if abs(rect) / page_area >= _PAGE_FRAME_COVERAGE:
            continue
        rects.append(rect)
    if not rects:
        return []

    clusters: list[list[fitz.Rect]] = []
    for rect in rects:
        expanded = fitz.Rect(rect) + (
            -_CLUSTER_GAP_PT,
            -_CLUSTER_GAP_PT,
            _CLUSTER_GAP_PT,
            _CLUSTER_GAP_PT,
        )
        members = [i for i, c in enumerate(clusters) if not (_union_all(c) & expanded).is_empty]
        if not members:
            clusters.append([rect])
            continue
        first = members[0]
        clusters[first].append(rect)
        for i in reversed(members[1:]):
            clusters[first].extend(clusters.pop(i))

    regions: list[FigureRegion] = []
    for cluster in clusters:
        box = _union_all(cluster)
        if abs(box) / page_area >= _PAGE_FRAME_COVERAGE:
            continue
        if len(cluster) < _MIN_DRAWING_ITEMS:
            continue
        if box.width < _MIN_REGION_SIDE_PT or box.height < _MIN_REGION_SIDE_PT:
            continue
        regions.append(
            FigureRegion(
                kind="drawing",
                bbox=(round(box.x0, 2), round(box.y0, 2), round(box.x1, 2), round(box.y1, 2)),
                drawing_items=len(cluster),
            )
        )
    return regions


# --------------------------------------------------------------------- #
# Embedded raster images
# --------------------------------------------------------------------- #
def _image_regions(doc: fitz.Document, page: fitz.Page) -> list[FigureRegion]:
    """Placed raster images on one page, each with its on-page bbox.

    One xref can be placed several times (or on several pages); every
    *placement* is its own region because the bbox differs, but the embedded
    source is scanned once per xref and shared.
    """
    regions: list[FigureRegion] = []
    scanned: dict[int, tuple[str | None, bool, str, int, int]] = {}
    for info in page.get_images(full=True):
        xref = info[0]
        placements = page.get_image_rects(xref)
        if not placements:
            continue
        if xref not in scanned:
            try:
                extracted = doc.extract_image(xref)
                xml, truncated, readable = _scan_embedded(extracted["image"], extracted["ext"])
                scanned[xref] = (
                    xml,
                    truncated,
                    readable,
                    int(extracted.get("width", 0)),
                    int(extracted.get("height", 0)),
                )
            except Exception:  # unreadable object — vision path still works
                scanned[xref] = (None, False, "vision-required", 0, 0)
        xml, truncated, readable, width, height = scanned[xref]
        for rect in placements:
            regions.append(
                FigureRegion(
                    kind="image",
                    bbox=(round(rect.x0, 2), round(rect.y0, 2), round(rect.x1, 2), round(rect.y1, 2)),
                    xref=xref,
                    pixel_width=width or None,
                    pixel_height=height or None,
                    embedded_xml=xml,
                    embedded_xml_truncated=truncated,
                    readable=readable,  # type: ignore[arg-type]
                )
            )
    return regions


# --------------------------------------------------------------------- #
# Sections: real bookmarks first, numbered-heading fallback second
# --------------------------------------------------------------------- #
def _sections_from_toc(doc: fitz.Document) -> list[SectionSpan]:
    toc = doc.get_toc()
    if not toc:
        return []
    spans: list[SectionSpan] = []
    for i, (level, title, page_1based) in enumerate(toc):
        start = max(0, page_1based - 1)
        end = doc.page_count - 1
        for level2, _, page2 in toc[i + 1 :]:
            if level2 <= level:
                end = max(start, page2 - 2)
                break
        spans.append(SectionSpan(title=title.strip(), level=level, start_page=start, end_page=end))
    return spans


def _sections_from_headings(doc: fitz.Document) -> list[SectionSpan]:
    spans: list[SectionSpan] = []
    for page_index in range(doc.page_count):
        text = doc[page_index].get_text("text")
        for line in text.splitlines()[:6]:
            match = _HEADING_RE.match(line)
            if not match:
                continue
            number, sep, title = match.groups()
            level = number.count(".") + 1
            spans.append(
                SectionSpan(
                    title=f"{number}{sep} {title.strip()}",
                    level=level,
                    start_page=page_index,
                    end_page=page_index,
                )
            )
            break
    for i, span in enumerate(spans):
        for later in spans[i + 1 :]:
            if later.level <= span.level:
                span.end_page = max(span.start_page, later.start_page - 1)
                break
        else:
            span.end_page = doc.page_count - 1
    return spans


# --------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------- #
def analyze_document(path: Path) -> DocumentMap:
    """Extract the full anatomy of a PDF (or DOCX — PyMuPDF converts it)."""
    with fitz.open(path) as doc:
        sections = _sections_from_toc(doc)
        toc_source: Literal["bookmarks", "headings", "none"] = "bookmarks"
        if not sections:
            sections = _sections_from_headings(doc)
            toc_source = "headings" if sections else "none"

        pages: list[PageAnatomy] = []
        for page_index in range(doc.page_count):
            page = doc[page_index]
            text = page.get_text("text")
            figures = _image_regions(doc, page) + _cluster_drawings(page)
            pages.append(
                PageAnatomy(
                    index=page_index,
                    text_length=len(text.strip()),
                    figures=figures,
                )
            )

        return DocumentMap(
            page_count=doc.page_count,
            toc_source=toc_source,
            sections=sections,
            pages=pages,
        )


def render_region_png(
    path: Path,
    *,
    page_index: int,
    bbox: tuple[float, float, float, float] | None = None,
    scale: float = 3.0,
    max_side_px: int = 2400,
) -> bytes:
    """Rasterise one page (or one bbox region of it) to PNG.

    ``scale`` 3.0 ≈ 216 DPI — the sds-reviewer pipeline renders at 250 DPI;
    the clip keeps the crop tight so small arrows/stereotypes survive. When
    the requested scale would exceed ``max_side_px`` on either axis it is
    reduced automatically (never raises) — callers that need more detail
    request sub-bboxes (tiles) instead.
    """
    with fitz.open(path) as doc:
        if page_index < 0 or page_index >= doc.page_count:
            raise ValueError(f"page_index {page_index} out of range (0..{doc.page_count - 1})")
        page = doc[page_index]
        clip = page.rect if bbox is None else fitz.Rect(*bbox) & page.rect
        if clip.is_empty:
            raise ValueError("bbox does not intersect the page")
        fitted = min(scale, max_side_px / clip.width, max_side_px / clip.height)
        fitted = max(0.5, fitted)  # never degrade below the readability floor
        pixmap = page.get_pixmap(matrix=fitz.Matrix(fitted, fitted), clip=clip, alpha=False)
        return pixmap.tobytes("png")


# --------------------------------------------------------------------- #
# Disk cache helpers (used by main.py; sidecars live next to the upload)
# --------------------------------------------------------------------- #
def docmap_sidecar(upload_path: Path) -> Path:
    return upload_path.with_name(upload_path.name + ".docmap.json")


def load_cached_map(upload_path: Path, sha256: str) -> DocumentMap | None:
    sidecar = docmap_sidecar(upload_path)
    if not sidecar.exists():
        return None
    try:
        payload = json.loads(sidecar.read_text(encoding="utf-8"))
        if payload.get("version") != DOCMAP_VERSION or payload.get("sha256") != sha256:
            return None
        return DocumentMap.model_validate(payload["map"])
    except Exception:
        return None  # corrupt cache — recompute


def store_cached_map(upload_path: Path, sha256: str, docmap: DocumentMap) -> None:
    payload = {
        "version": DOCMAP_VERSION,
        "sha256": sha256,
        "map": json.loads(docmap.model_dump_json()),
    }
    docmap_sidecar(upload_path).write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def render_cache_path(
    upload_path: Path,
    *,
    page_index: int,
    bbox: tuple[float, float, float, float] | None,
    scale: float,
) -> Path:
    key = hashlib.sha256(f"{page_index}|{bbox}|{scale}|{DOCMAP_VERSION}".encode()).hexdigest()[:16]
    return upload_path.with_name(f"{upload_path.name}.render.{key}.png")
