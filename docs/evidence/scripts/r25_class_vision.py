#!/usr/bin/env python3
"""
R25 — OTES class-diagram vision probe. POST 4 PNG pages (p160,
p167, p168, p169) containing class diagrams to /review with
image_b64 + per-page OCR text context. Goal: surface CLS-01/02/03
class-consistency issues from the LLM that single-UC text probes
(R21/R22) can't see.
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
PAGES = ["p160", "p167", "p168", "p169"]
OCR_DIR = SRC_DIR / "ocr"
OUT = Path("/tmp/r25_class_vision.json")


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
    results = []
    cls_match_count = 0
    sev_counts: dict[str, int] = {}

    for page in PAGES:
        png = SRC_DIR / "pages" / f"{page}-{page[1:]}.png"
        ocr_txt = (OCR_DIR / f"{page}.txt").read_text() if (OCR_DIR / f"{page}.txt").exists() else ""
        # Truncate OCR text to first 400 chars to keep payload reasonable
        ctx_text = ocr_txt[:400] or f"Class diagram page {page} from OTES SRS"
        payload = {
            "requirement_id": f"OTES-CLS-{page.upper()}",
            "text": ctx_text,
            "section": "3. SRS — Class Diagram",
            "page_index": int(page[1:]),
            "image_b64": b64(png),
        }
        try:
            r = post(payload)
        except urllib.error.HTTPError as e:
            print(f"FAIL {page}: HTTP {e.code}")
            if e.code == 429:
                print("  sleeping 30s")
                time.sleep(30)
                try:
                    r = post(payload)
                except Exception as e2:
                    print(f"  FAIL retry: {e2}")
                    continue
            else:
                continue
        except urllib.error.URLError as e:
            print(f"FAIL {page}: {e}")
            continue

        # Aggregate class-related issues (CLS-01/02/03 detection)
        all_issue_text = " ".join(
            i["quote"] + " " + i["suggestion"]
            for i in r.get("issues", [])
        )
        is_cls = any(
            kw in all_issue_text.lower()
            for kw in ["class", "attribute", "method", "field", "property",
                       "thuộc tính", "phương thức", "lớp", "diagram",
                       "consistency", "inconsisten", "mismatch"]
        )
        if is_cls:
            cls_match_count += 1
        for i in r.get("issues", []):
            sev_counts[i["severity"]] = sev_counts.get(i["severity"], 0) + 1

        results.append({
            "page": page,
            "png_size": png.stat().st_size,
            "score": r["score"],
            "issues": r["issues"],
            "model": r["model"],
            "cached": r.get("cached", False),
            "is_class_related": is_cls,
        })
        print(f"{page}: score={r['score']} issues={len(r['issues'])} "
              f"cls_match={is_cls} sev={sorted({i['severity'] for i in r['issues']})}")

    print("\n=== AGGREGATE ===")
    print(f"Pages probed:    {len(PAGES)}")
    print(f"Total findings:  {sum(sev_counts.values())}")
    print(f"Severities:      {sev_counts}")
    print(f"Class-related:   {cls_match_count} of {len(PAGES)} pages")

    OUT.write_text(json.dumps({
        "model_used": "gemini-3.5-flash (3.1-flash-lite fallback)",
        "pages": PAGES,
        "results": results,
        "sev_counts": sev_counts,
        "class_related_pages": cls_match_count,
    }, indent=2))
    print(f"\nFull JSON: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())