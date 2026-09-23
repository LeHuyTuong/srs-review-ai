r"""Probe 2026-09-23: "neu bang o dau tai lieu bi chuyen xuong cuoi thi co biet duoc khong?"

Do 3 kenh du lieu tren OTES that (server/5935d26a...-OTES_..._compressed.pdf):
  A. Vi tri bang THAT: PyMuPDF page.find_tables() -> (page_index, bbox, rows, cols).
  B. Caption "Table N" trong THAN tai lieu -> (number, page_index, thu tu dong trong trang).
  C. List of Tables (LoT) -> (number, printed_page KY VONG).
Roi:
  - Calibrate offset printed->pdf theo mode (y het BlueprintBuilder._calibrate nhung
    dung caption bang thay vi ten chuong, vi probe khong parse chapter list).
  - Kich ban (b): so vi tri that vs ky vong tren file GOC (do ty le mismatch san co).
  - Kich ban (a): MO PHONG move_page(1 trang chua bang dau tien -> cuoi), chay lai
    caption index + content hash cua vung bang, chung minh diff 2 phien ban bat duoc
    va "cung mot bang" nhan dien duoc bang hash noi dung ngay ca khi doi trang.

Cach dem (ghi ro theo luat repo):
  - "table region"  = 1 phan tu trong page.find_tables().tables (strategy mac dinh
    "lines"): mot bang keo dai 2 trang tinh la 2 region; khung trang tri/muc luc
    cung co the bi dem neu co duong ke — khong loai, bao nguyen so tho.
  - "caption"       = 1 DONG text khop ^Table\s+\d{1,3}\b tren trang KHONG phai trang
    LoT. Mot bang co the co 0 hoac >1 caption (caption lap lai o trang sau).
  - "LoT entry"     = 1 dong khop regex LoT (co so trang cuoi dong) tren trang co
    >=3 dong dang do (mirror minEntriesPerTocPage=3 cua TableOfContents.parse).
  - "thu tu trong trang" cua caption = thu tu dong trong page.get_text("text")
    (reading order), KHONG phai toa do y — du dung de biet caption nao dung truoc.
"""
import hashlib
import json
import re
import sys
import time
from collections import Counter
from pathlib import Path

import fitz  # PyMuPDF

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "server" / "5935d26a28934c6dae2af51adcb3e381-OTES_officially_document.docx_compressed.pdf"
OUT = REPO / "docs" / "evidence" / "table-position-probe-2026-09-23.json"

LOT_LINE = re.compile(
    r"^\s*table\s+(\d{1,3})\s*[.:\u2013-]?\s*(\S.*?)\s*[\s.\u00b7]*\s(\d{1,4})\s*$",
    re.IGNORECASE,
)
CAPTION = re.compile(r"^\s*Table\s+(\d{1,3})\b[.:]?\s*(.*)$")
WINDOW = 3  # mirror BlueprintBuilder.captionSearchWindow


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def table_regions(doc):
    """Kenh A: moi region find_tables() -> (page, bbox, rows, cols, content_hash)."""
    regions = []
    for pno in range(doc.page_count):
        page = doc[pno]
        try:
            finder = page.find_tables()
        except Exception as exc:  # khong de 1 trang xau giet ca probe
            regions.append({"page": pno, "error": str(exc)})
            continue
        for tab in finder.tables:
            try:
                cells = tab.extract()
                digest = sha256(json.dumps(cells, ensure_ascii=False).encode())[:16]
            except Exception:
                cells, digest = None, None
            regions.append({
                "page": pno,
                "bbox": [round(v, 1) for v in tab.bbox],
                "rows": getattr(tab, "row_count", None),
                "cols": getattr(tab, "col_count", None),
                "content_hash": digest,
                "first_cell": (str(cells[0][0])[:60] if cells and cells[0] else None),
            })
    return regions


LOT_LABEL = re.compile(r"^\s*Table\s+(\d{1,3})\s*[.:]?\s*$", re.IGNORECASE)
LOT_LABEL_TITLE = re.compile(r"^\s*Table\s+(\d{1,3})\s*[.:]\s+(\S.*?)\s*$", re.IGNORECASE)
PAGENUM = re.compile(r"^\d{1,4}$")
FOOTER_Y0 = 700.0
"""Region co bbox.y0 >= nguong nay nam o chan trang A4 (cao 842pt): footer
'Page | N' bi find_tables dem thanh bang 1x3 tren moi trang — cung lop nhieu
'khung vien trang' cua _cluster_drawings trong docmap.py."""


def lot_pages_and_entries(doc):
    """Kenh C: trang LoT (>=3 entry) + entry (number, title, printed_page).

    LoT cua OTES bi PyMuPDF tach thanh 3 DONG/entry: 'Table 12.' /
    '<Student> View study schedule' / '31' — khac app (syncfusion +
    joinVisualLines gop thanh 1 dong nen regex 1 dong cua table_of_contents.dart
    khop duoc). State machine: label -> title (>=1 dong) -> dong toan so trang.
    Giu ca regex 1 dong cho tai lieu xuat khac."""
    per_page = {}
    for pno in range(doc.page_count):
        lines = [ln.strip() for ln in doc[pno].get_text("text").splitlines()]
        hits = []
        i = 0
        while i < len(lines):
            m1 = LOT_LINE.match(lines[i])
            if m1:
                hits.append((int(m1.group(1)), m1.group(2).strip(), int(m1.group(3))))
                i += 1
                continue
            # Dang 'Table 100. <Buttons> ...' label+title CUNG dong, so trang dong sau
            # (trang LoT thu 3 cua OTES dung dang nay — 15 entry dau tien bi sot
            # khi chi bat 2 dang kia).
            m3 = LOT_LABEL_TITLE.match(lines[i])
            if m3:
                title_parts = [m3.group(2)]
                j = i + 1
                while (j < len(lines) and lines[j] and not PAGENUM.match(lines[j])
                       and not LOT_LABEL.match(lines[j])
                       and not LOT_LABEL_TITLE.match(lines[j])):
                    title_parts.append(lines[j])
                    j += 1
                if j < len(lines) and PAGENUM.match(lines[j]):
                    hits.append((int(m3.group(1)), " ".join(title_parts), int(lines[j])))
                    i = j + 1
                    continue
            m2 = LOT_LABEL.match(lines[i])
            if m2:
                number = int(m2.group(1))
                title_parts = []
                j = i + 1
                while (j < len(lines) and lines[j] and not PAGENUM.match(lines[j])
                       and not LOT_LABEL.match(lines[j])):
                    title_parts.append(lines[j])
                    j += 1
                if title_parts and j < len(lines) and PAGENUM.match(lines[j]):
                    hits.append((number, " ".join(title_parts), int(lines[j])))
                    i = j + 1
                    continue
            i += 1
        if hits:
            per_page[pno] = hits
    lot_pages = {p for p, h in per_page.items() if len(h) >= 3}
    entries = []
    seen = set()
    for p in sorted(lot_pages):
        for number, title, printed in per_page[p]:
            key = (number, title)
            if key in seen:
                continue
            seen.add(key)
            entries.append({"number": number, "title": title, "printed_page": printed, "lot_page": p})
    return sorted(lot_pages), entries



def caption_index(doc, lot_pages):
    """Kenh B: caption 'Table N' trong than -> (number, page, line_ordinal, text)."""
    caps = []
    for pno in range(doc.page_count):
        if pno in lot_pages:
            continue
        for ordinal, line in enumerate(doc[pno].get_text("text").splitlines()):
            m = CAPTION.match(line.strip())
            if m:
                caps.append({
                    "number": int(m.group(1)),
                    "page": pno,
                    "line_ordinal": ordinal,
                    "text": line.strip()[:90],
                })
    return caps


def calibrate_and_compare(lot_entries, captions):
    """Offset = mode(caption_page - (printed-1)); delta>WINDOW => mismatch."""
    cap_page = {}
    for c in captions:  # caption dau tien cua moi so hieu (doc order)
        cap_page.setdefault(c["number"], c["page"])
    pairs = [(e["number"], e["printed_page"], cap_page[e["number"]])
             for e in lot_entries if e["number"] in cap_page]
    votes = Counter(found - (printed - 1) for _, printed, found in pairs)
    offset = votes.most_common(1)[0][0] if votes else 0
    resolved, mismatch = [], []
    for number, printed, found in pairs:
        delta = found - (printed - 1 + offset)
        (resolved if abs(delta) <= WINDOW else mismatch).append(
            {"number": number, "printed_page": printed, "found_page": found, "delta": delta})
    lot_only = [e["number"] for e in lot_entries if e["number"] not in cap_page]
    cap_only = sorted({c["number"] for c in captions} - {e["number"] for e in lot_entries})
    return {"offset": offset, "vote_distribution": dict(sorted(votes.items())),
            "resolved_in_window": resolved, "mismatch_outside_window": mismatch,
            "lot_entry_without_caption": lot_only, "caption_without_lot_entry": cap_only}


def main():
    t0 = time.monotonic()
    raw = SRC.read_bytes()
    doc = fitz.open(stream=raw, filetype="pdf")
    n = doc.page_count
    bookmarks = bool(doc.get_toc())

    regions = table_regions(doc)
    lot_pages, lot_entries = lot_pages_and_entries(doc)
    captions = caption_index(doc, set(lot_pages))
    cmp_original = calibrate_and_compare(lot_entries, captions)

    # --- Kich ban (a): mo phong move trang chua caption dau tien xuong cuoi ---
    body_captions = [c for c in captions if c["page"] not in set(lot_pages)]
    first_cap = min(body_captions, key=lambda c: (c["page"], c["line_ordinal"])) if body_captions else None
    move = None
    if first_cap is not None:
        src_page = first_cap["page"]
        hashes_before = {r["content_hash"] for r in regions
                         if r.get("page") == src_page and r.get("content_hash")}
        moved = fitz.open(stream=raw, filetype="pdf")
        moved.move_page(src_page, -1)  # -1 = cuoi tai lieu
        moved_lot_pages, moved_lot_entries = lot_pages_and_entries(moved)
        moved_captions = caption_index(moved, set(moved_lot_pages))
        moved_regions = table_regions(moved)
        dest_page = moved.page_count - 1
        same_cap = [c for c in moved_captions if c["number"] == first_cap["number"]]
        hashes_after_dest = {r["content_hash"] for r in moved_regions
                             if r.get("page") == dest_page and r.get("content_hash")}
        orig_by_num = {}
        for c in captions:
            orig_by_num.setdefault(c["number"], c["page"])
        moved_by_num = {}
        for c in moved_captions:
            moved_by_num.setdefault(c["number"], c["page"])
        # move_page(p, -1): trang p -> cuoi; cac trang SAU p tut xuong 1.
        # delta==0: truoc trang move; delta==-1: tut vi reorder; khac: bi move that.
        classified = {"unchanged": 0, "shifted_by_reorder": 0, "moved_with_page": []}
        for num in sorted(moved_by_num):
            if num not in orig_by_num:
                continue
            delta = moved_by_num[num] - orig_by_num[num]
            if delta == 0:
                classified["unchanged"] += 1
            elif delta == -1:
                classified["shifted_by_reorder"] += 1
            else:
                classified["moved_with_page"].append(
                    {"number": num, "from_page": orig_by_num[num],
                     "to_page": moved_by_num[num], "delta": delta})
        lot_stale = (
            {(e["number"], e["printed_page"]) for e in lot_entries}
            == {(e["number"], e["printed_page"]) for e in moved_lot_entries})
        move = {
            "moved_page_from": src_page,
            "moved_page_to": dest_page,
            "probe_caption": first_cap,
            "same_caption_after_move": same_cap,
            "content_hashes_on_src_page_before": sorted(hashes_before),
            "content_hashes_on_dest_page_after": sorted(hashes_after_dest),
            "content_identity_preserved": bool(hashes_before & hashes_after_dest),
            "lot_entries_unchanged_after_move": lot_stale,
            "caption_page_deltas": classified,
        }
        moved.close()

    ok_regions = [r for r in regions if "bbox" in r]
    footer_regions = [r for r in ok_regions if r["bbox"][1] >= FOOTER_Y0]
    content_regions = [r for r in ok_regions if r["bbox"][1] < FOOTER_Y0]
    pages_with_tables = sorted({r["page"] for r in content_regions})
    pages_with_caption = sorted({c["page"] for c in captions})
    uncaptioned_pages = [p for p in pages_with_tables
                         if p not in set(pages_with_caption) and p not in set(lot_pages)]
    out = {
        "kind": "capability_probe_not_accuracy_score",
        "date": "2026-09-23",
        "source": SRC.name,
        "source_sha256": sha256(raw),
        "pymupdf": fitz.__doc__.split(":")[0].strip(),
        "page_count": n,
        "has_bookmarks": bookmarks,
        "counting": {
            "table_region": "1 phan tu find_tables().tables, strategy mac dinh, khong loai khung/LoT",
            "caption": "1 dong text khop ^Table\\s+\\d{1,3} ngoai trang LoT",
            "lot_entry": "dong khop regex LoT tren trang co >=3 dong dang do, dedup (number,title)",
            "window": WINDOW,
        },
        "channel_A_table_regions": {
            "total_regions_raw": len(ok_regions),
            "footer_strip_regions": len(footer_regions),
            "content_regions": len(content_regions),
            "pages_with_content_tables": len(pages_with_tables),
            "errors": [r for r in regions if "error" in r],
            "sample_first5": ok_regions[:5],
            "sample_content_first5": content_regions[:5],
        },
        "channel_B_captions": {
            "total_caption_lines": len(captions),
            "distinct_numbers": len({c["number"] for c in captions}),
            "sample_first5": captions[:5],
        },
        "channel_C_lot": {
            "lot_pages_0based": lot_pages,
            "total_entries": len(lot_entries),
            "distinct_numbers": len({e["number"] for e in lot_entries}),
            "sample_first5": lot_entries[:5],
        },
        "scenario_b_expected_vs_actual_on_original": {
            "compared_pairs": len(cmp_original["resolved_in_window"]) + len(cmp_original["mismatch_outside_window"]),
            **cmp_original,
        },
        "scenario_a_move_page_simulation": move,
        "uncaptioned_table_pages": {
            "definition": "trang co >=1 table region nhung KHONG co caption nao tren trang do (ngoai trang LoT)",
            "pages_0based": uncaptioned_pages,
            "count": len(uncaptioned_pages),
        },
        "elapsed_seconds": round(time.monotonic() - t0, 2),
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    doc.close()
    print("sha256", out["source_sha256"], "| pages", n, "| bookmarks", bookmarks)
    print("regions raw", out["channel_A_table_regions"]["total_regions_raw"],
          "| footer", out["channel_A_table_regions"]["footer_strip_regions"],
          "| content", out["channel_A_table_regions"]["content_regions"],
          "on", out["channel_A_table_regions"]["pages_with_content_tables"], "pages")
    print("captions", out["channel_B_captions"]["total_caption_lines"],
          "distinct", out["channel_B_captions"]["distinct_numbers"])
    print("lot pages", lot_pages, "entries", out["channel_C_lot"]["total_entries"])
    print("scenario_b pairs", out["scenario_b_expected_vs_actual_on_original"]["compared_pairs"],
          "offset", cmp_original["offset"],
          "mismatch", len(cmp_original["mismatch_outside_window"]))
    if move:
        deltas = move["caption_page_deltas"]
        print("moved page", move["moved_page_from"], "->", move["moved_page_to"],
              "| identity_preserved", move["content_identity_preserved"],
              "| lot_stale", move["lot_entries_unchanged_after_move"],
              "| moved_with_page", len(deltas["moved_with_page"]),
              "| shifted", deltas["shifted_by_reorder"],
              "| unchanged", deltas["unchanged"])
    print("uncaptioned table pages:", len(uncaptioned_pages))
    print("elapsed", out["elapsed_seconds"], "s")
    print("WROTE", OUT)


if __name__ == "__main__":
    sys.exit(main())
