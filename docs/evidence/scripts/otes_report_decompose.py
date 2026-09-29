#!/usr/bin/env python3
"""WP8 follow-up — decompose the 232-finding OTES docx report (2026-09-26)
into its report sections, so the gap against the 09-29 batch run (122
verified issues on the same 91-unit parse) can be attributed:
model findings vs offline checks vs human rows, plus the inventory count
and the model identity the report itself declares.

Reads the .docx with stdlib zipfile only (the docx is a ZIP; the reader
needs word/document.xml). Prints every number it computes; no asserts.
"""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DOCX = r"D:\Download\srs-review-OTES_officially_document.docx_compressed-vi-2026-09-26.docx"

NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def paragraphs(xml_bytes):
    root = ET.fromstring(xml_bytes)
    out = []
    for p in root.iter(NS + "p"):
        text = "".join(t.text or "" for t in p.iter(NS + "t")).strip()
        if text:
            out.append(text)
    return out


def main():
    with zipfile.ZipFile(DOCX) as z:
        xml = z.read("word/document.xml")
    paras = paragraphs(xml)
    print("total paragraphs:", len(paras))

    # The section headers the docx builder authors (report_strings picks):
    markers = [
        "1. Tóm tắt lượt chấm",
        "2. Điểm theo mục tài liệu",
        "3. Lỗi do model phát hiện",
        "4. Kiểm tra ngoại tuyến",
        "5. Lỗi do người review ghi",
        "6. Danh mục tài liệu",
        "7. Giới hạn và ghi chú bằng chứng",
    ]
    idx = {}
    for m in markers:
        for i, p in enumerate(paras):
            if p.startswith(m):
                idx[m] = i
                break
    for m in markers:
        print(("found " if m in idx else "MISSING ") + m, idx.get(m, ""))

    order = sorted((i, m) for m, i in idx.items())

    def slice_len(marker):
        """Paragraph count between this marker and the next heading."""
        start = idx[marker]
        ends = [i for i, _ in order if i > start]
        end = min(ends) if ends else len(paras)
        return end - start

    for m in markers:
        if m in idx:
            print(f"section '{m}' spans {slice_len(m)} paragraphs")

    # Count finding rows inside section 3 (model findings): each row carries a
    # verification chip. Vietnamese labels from report_strings 1.0.0 era:
    exact = sum(1 for p in paras if "khớp nguyên văn" in p)
    fuzzy = sum(1 for p in paras if "khớp gần đúng" in p)
    print("paragraphs mentioning 'khớp nguyên văn':", exact)
    print("paragraphs mentioning 'khớp gần đúng':", fuzzy)

    # Model identity + rubric label the report declares.
    for p in paras:
        if "model" in p.lower() and ("gemini" in p.lower() or "mock" in p.lower()):
            print("model line:", p[:160])
            break
    for p in paras:
        if "thang điểm" in p.lower() or "rubric" in p.lower():
            print("rubric line:", p[:160])
            break

    # Inventory: count unit ids listed in section 6 (Danh mục tài liệu).
    if "6. Danh mục tài liệu" in idx:
        start = idx["6. Danh mục tài liệu"]
        ends = [i for i, _ in order if i > start]
        end = min(ends) if ends else len(paras)
        ids = []
        for p in paras[start + 1 : end]:
            m = re.match(r"^([A-Z]{2,4}[-–][A-Za-z0-9.]+)", p)
            if m:
                ids.append(m.group(1))
        print("inventory unit rows:", len(ids))
        print("inventory sample:", ids[:8])

    # Severity chips inside section 3, if the text keeps them as words.
    start3 = idx.get("3. Lỗi do model phát hiện")
    if start3 is not None:
        ends = [i for i, _ in order if i > start3]
        end3 = min(ends) if ends else len(paras)
        sev = {"Nghiêm trọng": 0, "Trung bình": 0, "Nhẹ": 0}
        for p in paras[start3:end3]:
            for k in sev:
                if k in p:
                    sev[k] += 1
        print("severity chip mentions inside section 3:", sev)

    # Dropped-quote line (the anti-hallucination metric the report prints).
    for p in paras:
        if "bị loại" in p or "Trích dẫn bị loại" in p:
            print("dropped line:", p[:200])


if __name__ == "__main__":
    main()
