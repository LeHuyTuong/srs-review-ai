"""P0a probe — vision co THAT DOC DOC DUOC khong?

Ke chuyen "vision chua tung chay tren tai lieu that" (plan 8 do duoc
namespace `diagram` = 0 entry) vao bang chung. Chay describe that tren
figure that cua HisWise (tieng Anh) va OTES (tieng Viet), roi do:

  - so element / relation ma model tra ve
  - ty le CHU DOC DUOC:  elements / (elements + unreadable)
  - mat do phat hien so voi text layer cua PDF — text layer la CHUAN,
    KHONG phai mo hinh (khong tu xay ra chuan de do chinh no)

Chay truc tiep provider + docmap, khong qua HTTP: khong muon mot probe do
lai mot cai de bi ban loi HTTP rac o giua duong.

Chay:
    cd server && .venv\\Scripts\\python.exe ..\\docs\\evidence\\scripts\\probe_vision_reality.py

KHONG in key. KHONG ghi vao .cache/ — cache rieng .vision-probe-cache.json
de khong lam hong 238 ket qua da tra tien cua cac lượt chay truoc.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import re
import sys
import time
from pathlib import Path

SERVER = Path(__file__).resolve().parents[3] / "server"
sys.path.insert(0, str(SERVER))
os.chdir(SERVER)

from app.config.settings import Settings  # noqa: E402
from app.infrastructure import docmap  # noqa: E402
from app.infrastructure.diagram import (  # noqa: E402
    DESCRIBE_SYSTEM,
    DIAGRAM_PROMPT_VERSION,
    LLM_DIAGRAM_DESCRIBE_SCHEMA,
    DiagramDescribe,
    DiagramType,
    describe_user_prompt,
)
from app.infrastructure.llm.gemini import GeminiProvider  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "vision-reality-2026-09-26.json"
CACHE = Path(__file__).resolve().parent / ".vision-probe-cache.json"

# (nhan, ten file) — hai tai lieu that da co trong repo.
TARGETS = [
    ("HisWise-EN", "3b662b387392412f81870547ac69ac73-_HisWise_SDS Document.pdf"),
    ("OTES-VI", "5935d26a28934c6dae2af51adcb3e381-OTES_officially_document.docx_compressed.pdf"),
]

PAGES_PER_DOC = 4
"""Keo danh sach roi chay het. Ket luan tu MOT trang la do lai — dung sau
khi tung gap 3 lan (dong 'Dung ket luan tu 1 trang' trong AGENTS.md)."""

SCALE = 4.0
"""render_region_png tu giam scale khi vuot max_side_px=2400; 4.0 la
~288 DPI cho crop nho. Doc muc do giam thuc te trong bao cao."""

_ALNUM = re.compile(r"[A-Za-z0-9À-ỹ]")


def _load_cache() -> dict:
    if CACHE.exists():
        return json.loads(CACHE.read_text(encoding="utf-8"))
    return {}


def _save_cache(cache: dict) -> None:
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")


def _pick_figures(document_map: docmap.DocumentMap, wanted: int) -> list:
    """Cac figure region cua nhung trang co nhieu hinh nhat.

    Tra ve cap (page_index, region). Chi so trang doc tu PageAnatomy.index —
    """
    ranked = []
    for page in document_map.pages:
        # Page index lives on PageAnatomy.index, NOT on FigureRegion.
        for region in page.figures:
            ranked.append((len(page.figures), page.index, region))
    ranked.sort(key=lambda t: (-t[0], t[1]))
    out, seen = [], set()
    for _, page_index, region in ranked:
        if page_index in seen:
            continue
        seen.add(page_index)
        out.append((page_index, region))
        if len(out) >= wanted:
            break
    return out


def _text_in_region(pdf_path: Path, page_index: int, bbox) -> str:
    """Text that really sits inside the figure's box.

    Ground truth a describe response can be checked against: the PDF's own
    text layer, not the model. For a vector UML diagram these are exactly
    the labels the author placed.
    """
    import fitz  # noqa: PLC0415

    with fitz.open(pdf_path) as doc:
        page = doc[page_index]
        clip = (fitz.Rect(*bbox) & page.rect) if bbox else page.rect
        return page.get_text("text", clip=clip)


async def probe_doc(provider, label, pdf_path, document_map, cache) -> dict:
    """Mo ta describe cho tung figure va ghi lai chi so doc duoc."""
    rows = []
    figures = _pick_figures(document_map, PAGES_PER_DOC)
    if not figures:
        return {"doc": label, "file": pdf_path.name, "rows": [], "note": "khong co figure region"}

    for page_index, region in figures:
        key = f"{label}|p{page_index}|{region.bbox}"
        truth = _text_in_region(pdf_path, page_index, region.bbox)
        truth_alnum = len(_ALNUM.findall(truth))
        png = docmap.render_region_png(
            pdf_path, page_index=page_index, bbox=region.bbox, scale=SCALE
        )

        tokens = 0
        if key in cache:
            raw, elapsed, was_cached = cache[key], 0.0, True
        else:
            started = time.perf_counter()
            try:
                # GenerateJsonResult is a 2-tuple (data, model); usage is a
                # named attribute, NOT a third unpacked value.
                result = await provider.generate_json(
                    system=DESCRIBE_SYSTEM,
                    user=describe_user_prompt(
                        page_index=page_index,
                        diagram_type=DiagramType.CLASS,
                        context_text=truth[:2000],
                    ),
                    schema=LLM_DIAGRAM_DESCRIBE_SCHEMA,
                    image_b64=base64.b64encode(png).decode("ascii"),
                )
            except Exception as exc:  # noqa: BLE001 - probe reports, never raises
                message = f"{type(exc).__name__}: {exc}"
                rows.append({"page_index": page_index, "error": message})
                print(f"  p{page_index:>3}  LOI: {message}", flush=True)
                continue
            elapsed = time.perf_counter() - started
            raw, was_cached = result.data, False
            tokens = result.usage.get("total_tokens", 0)
            cache[key] = raw
            _save_cache(cache)

        described = DiagramDescribe.model_validate(raw)
        read = len(described.elements)
        unread = len(described.unreadable)
        total = read + unread
        row = {
            "page_index": page_index,
            "kind": region.kind,
            "png_kb": round(len(png) / 1024),
            "truth_alnum_chars": truth_alnum,
            "elements": read,
            "relations": len(described.relations),
            "unreadable": unread,
            "readable_ratio": round(read / total, 3) if total else None,
            "elements_per_1k_truth": round(read / max(truth_alnum / 1000, 1), 2),
            "sample_elements": described.elements[:8],
            "unreadable_sample": described.unreadable[:5],
            "elapsed_s": round(elapsed, 1),
            "cached": was_cached,
        }
        if tokens:
            row["total_tokens"] = tokens
        rows.append(row)
        print(
            f"  p{page_index:>3} {row['png_kb']:>4}KB  "
            f"truth={truth_alnum:>5}ch  elem={read:>3}  rel={row['relations']:>3}  "
            f"unread={unread:>3}  ratio={row['readable_ratio']}  "
            f"elem/1k={row['elements_per_1k_truth']}  {row['elapsed_s']}s"
            + ("  [cached]" if was_cached else ""),
            flush=True,
        )
    return {"doc": label, "file": pdf_path.name, "rows": rows}


async def main() -> int:
    settings = Settings()
    if not settings.gemini_api_key:
        print("GEMINI_API_KEY chua cau hinh — P0a khong chay duoc.")
        print("Day KHONG phai ket luan ve vision; day la thieu cau hinh.")
        return 2
    if settings.mock_mode:
        print("MOCK_MODE=true — se do nham, khong phai vision that. Tat no truoc.")
        return 2

    print(f"model      : {settings.gemini_model}")
    print(f"fallback   : {settings.gemini_fallback_model}")
    print(f"prompt ver : {DIAGRAM_PROMPT_VERSION}")
    print(f"render     : scale={SCALE} (docmap giam ve max_side_px khi can)")
    print()

    provider = GeminiProvider(settings)
    cache = _load_cache()
    report = {
        "measured_on": "2026-09-26",
        "model": settings.gemini_model,
        "prompt_version": DIAGRAM_PROMPT_VERSION,
        "render_scale_requested": SCALE,
        "pages_per_doc": PAGES_PER_DOC,
        "docs": [],
    }

    for label, name in TARGETS:
        path = Path(name)
        if not path.exists():
            print(f"[bo qua] khong tim thay {name}")
            continue
        document_map = docmap.analyze_document(path)
        n_fig = sum(len(p.figures) for p in document_map.pages)
        print(f"== {label}  ({document_map.page_count} trang, {n_fig} figure region)")
        report["docs"].append(await probe_doc(provider, label, path, document_map, cache))
        print()

    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("=" * 68)
    for entry in report["docs"]:
        rows = [r for r in entry["rows"] if "error" not in r]
        if not rows:
            print(f"{entry['doc']}: khong co duong do duoc")
            continue
        ratios = [r["readable_ratio"] for r in rows if r["readable_ratio"] is not None]
        mean_ratio = round(sum(ratios) / len(ratios), 3) if ratios else None
        mean_density = round(sum(r["elements_per_1k_truth"] for r in rows) / len(rows), 2)
        errors = [r for r in entry["rows"] if "error" in r]
        print(
            f"{entry['doc']:<12} {len(rows)} trang  "
            f"readable_ratio TB={mean_ratio}  elem/1k-chu TB={mean_density}"
            + (f"  [{len(errors)} loi]" if errors else "")
        )
        for r in errors:
            print(f"    p{r['page_index']}: {r['error']}")
    print(f"\nghi {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
