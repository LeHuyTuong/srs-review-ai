#!/usr/bin/env python3
"""
R29 — Full OTES vision probe. POST all 50 PNGs (34 imgs/ + 16 pages/)
to /review with image_b64 + per-page OCR text context. Goal: close the
CLS-01/02/03 gate via vision path and surface any cross-artifact
issues visible in diagrams.
"""

from __future__ import annotations

import base64
import json
import urllib.request
import urllib.error
import sys
import time
from pathlib import Path

URL = "http://127.0.0.1:8000/review"
SRC_DIR = Path("/Users/lehuytuong/dsh-chat/otes")
PAGES_DIR = SRC_DIR / "pages"
IMGS_DIR = SRC_DIR / "imgs"
OCR_DIR = SRC_DIR / "ocr"
OUT = Path("/tmp/r29_full_vision.json")

# Already probed in R25
R25_DONE = {"p160", "p167", "p168", "p169"}


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def post(payload: dict) -> dict:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def main() -> int:
    # Build PNG list with metadata
    pngs: list[tuple[str, Path]] = []
    for p in sorted(PAGES_DIR.glob("*.png")):
        pngs.append((p.stem, p))
    for p in sorted(IMGS_DIR.glob("*.png")):
        pngs.append((p.stem, p))

    print(f"Total PNGs discovered: {len(pngs)}")

    results = []
    cls_pages = 0
    sev_counts: dict[str, int] = {}

    for i, (stem, png) in enumerate(pngs, 1):
        # Page number is the second segment after the dash (e.g. p160-160 → "160",
        # dbg-160 → "160", hi-159 → "159"). The first segment is the prefix
        # (p/h/dbg/hi) — see R29 AGENTS.md "Bẫy đã trả giá" section: UC count
        # varies by counting method, so each PNG needs its actual page index.
        page_num = stem.split("-")[1]
        page_id = f"{stem.split('-')[0]}{page_num}"
        ocr_path = OCR_DIR / f"p{page_num}.txt"
        if not ocr_path.exists():
            ocr_path = OCR_DIR / f"h{page_num}.txt"
        ocr_txt = ocr_path.read_text() if ocr_path.exists() else ""
        ctx_text = ocr_txt[:500] or f"OTES diagram page {stem}"

        # Skip already-done R25 pages (R25 probed p160/p167/p168/p169)
        if page_id in R25_DONE:
            print(f"[{i:02d}/{len(pngs)}] {stem}: SKIP (R25)")
            continue

        payload = {
            "requirement_id": f"OTES-VIS-{stem.upper().replace('-', '_')}",
            "text": ctx_text,
            "section": "3. SRS — Diagrams",
            "page_index": int(page_num),
            "image_b64": b64(png),
        }

        t0 = time.time()
        try:
            r = post(payload)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                print(f"[{i:02d}/{len(pngs)}] {stem}: HTTP 429, sleeping 10s")
                time.sleep(10)
                try:
                    r = post(payload)
                except Exception as e2:
                    print(f"[{i:02d}/{len(pngs)}] {stem}: FAIL retry {e2}")
                    continue
            else:
                print(f"[{i:02d}/{len(pngs)}] {stem}: FAIL HTTP {e.code}")
                continue
        except urllib.error.URLError as e:
            print(f"[{i:02d}/{len(pngs)}] {stem}: FAIL {e}")
            continue

        # Classify
        all_text = " ".join(
            i["quote"] + " " + i["suggestion"]
            for i in r.get("issues", [])
        )
        is_cls = any(
            kw in all_text.lower()
            for kw in ["class", "attribute", "method", "field", "property",
                       "thuộc tính", "phương thức", "lớp", "diagram",
                       "consistency", "inconsisten", "mismatch"]
        )
        if is_cls:
            cls_pages += 1
        for issue in r.get("issues", []):
            sev_counts[issue["severity"]] = sev_counts.get(issue["severity"], 0) + 1

        results.append({
            "stem": stem,
            "score": r["score"],
            "issues": r["issues"],
            "is_class_related": is_cls,
            "elapsed_s": round(time.time() - t0, 2),
        })
        print(
            f"[{i:02d}/{len(pngs)}] {stem}: score={r['score']} "
            f"issues={len(r['issues'])} cls={is_cls} "
            f"({time.time() - t0:.1f}s)"
        )

    print("\n=== AGGREGATE ===")
    print(f"PNGs probed:        {len(results)} of {len(pngs)} (skipped {len(pngs) - len(results)} R25)")
    print(f"Total findings:     {sum(sev_counts.values())}")
    print(f"Severities:         {sev_counts}")
    print(f"Class-related:      {cls_pages} of {len(results)} pages")
    print(f"R25 + R29 CLS pages: {4 + cls_pages} (R25 hit 2 of 4)")

    OUT.write_text(json.dumps({
        "model_used": "gemini-3.5-flash (3.1-flash-lite fallback)",
        "results": results,
        "sev_counts": sev_counts,
        "class_related_pages": cls_pages,
        "total_pages_probed": len(results),
    }, indent=2))
    print(f"\nFull JSON: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())