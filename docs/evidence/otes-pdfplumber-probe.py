"""Bounded offline extraction probe, not a semantic SRS parser or accuracy benchmark."""
import hashlib
import json
import time
from pathlib import Path
import pdfplumber

source = Path('/Users/lehuytuong/Downloads/OTES_officially_document.docx.pdf')
selected = [31, 32, 55, 72, 82, 83, 84, 122, 154]
results = []
start = time.monotonic()
with pdfplumber.open(source) as pdf:
    for page_no in selected:
        p = pdf.pages[page_no - 1]
        words = p.extract_words()
        tables = p.find_tables()
        text_tables = p.find_tables(table_settings={
            'vertical_strategy': 'text', 'horizontal_strategy': 'text'
        })
        results.append({
            'pdf_page': page_no,
            'chars': len(p.chars),
            'words': len(words),
            'images': len(p.images),
            'vector_lines': len(p.lines),
            'vector_rects': len(p.rects),
            'default_table_count': len(tables),
            'text_strategy_table_count': len(text_tables),
            'table_shapes_default': [[len(t.rows), len(t.columns)] for t in tables],
            'table_shapes_text_strategy': [[len(t.rows), len(t.columns)] for t in text_tables],
            'first_word_bbox': {k: words[0][k] for k in ['x0', 'top', 'x1', 'bottom']} if words else None,
            'has_native_text': bool(p.extract_text()),
        })
        p.close()
output = {
    'kind': 'capability_probe_not_accuracy_score',
    'parser': 'pdfplumber',
    'version': pdfplumber.__version__,
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'selected_pdf_pages': selected,
    'elapsed_seconds': round(time.monotonic() - start, 3),
    'no_ocr_or_llm_calls': True,
    'warning': 'Table detection and bounding boxes do not prove correct cells, UC boundaries, cross-page merging, or UML understanding.',
    'pages': results,
}
Path('/tmp/otes-pdfplumber-probe.json').write_text(json.dumps(output, indent=2)+'\n')
print(json.dumps(output, indent=2))
assert all(p['has_native_text'] for p in results), 'Selected text-bearing pages unexpectedly have no text'
assert all(p['first_word_bbox'] is not None for p in results), 'Word provenance missing'
print('PASS: selected pages yield text and word bounding boxes; semantic accuracy NOT verified.')
