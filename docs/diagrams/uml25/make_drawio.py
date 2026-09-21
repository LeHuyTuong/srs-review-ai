#!/usr/bin/env python3
"""Build self-contained draw.io files for the canonical UML set."""

from __future__ import annotations

import base64
import hashlib
import html
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
RENDERED = HERE / "rendered"
OUT = HERE / "drawio"

TITLE_BY_BASE = {
    "01-architecture-overview": "Tổng quan kiến trúc",
    "02-deployment-view": "Triển khai tổng quan",
    "03-component-view": "Thành phần tổng quan",
    "04-activity-main-swimlanes": "Hoạt động chính theo làn",
    "05-package-layers": "Các lớp gói",
    "06-persistence-view": "Quan điểm lưu trữ",
    "07-interaction-overview": "Tổng quan tương tác",
    "08-sequence-import-parse": "Tuần tự nhập và phân tích",
    "09-sequence-review": "Tuần tự review",
    "10-sequence-diagram-audit": "Tuần tự audit sơ đồ",
    "11-sequence-ask": "Tuần tự hỏi tài liệu",
    "12-sequence-export-share": "Tuần tự xuất và chia sẻ",
    "13-sequence-upload-groundwork": "Nền tảng tải lên",
    "14-class-domain-application": "Lớp miền và ứng dụng",
    "15-state-review-run": "Trạng thái lượt review",
    "16-state-finding-lifecycle": "Vòng đời finding",
    "17-use-case-overview": "Tổng quan use case",
    "18-activity-main-swimlanes": "Hoạt động chính theo làn PlantUML",
    "19-component-architecture": "Kiến trúc thành phần PlantUML",
    "20-communication-review": "Giao tiếp review PlantUML",
    "21-deployment-runtime": "Triển khai runtime PlantUML",
    "22-communication-review": "Giao tiếp review Mermaid",
    "23-data-model-erd": "Mô hình dữ liệu ERD",
}


def _svg_size(svg: Path) -> tuple[float, float]:
    text = svg.read_text(encoding="utf-8")
    match = re.search(r"\bviewBox=\"([^\"]+)\"", text)
    if match:
        values = [float(v) for v in re.split(r"[\s,]+", match.group(1).strip()) if v]
        if len(values) == 4 and values[2] and values[3]:
            return values[2], values[3]
    match = re.search(r"\bwidth=\"([^\"]+)\"\s+\bheight=\"([^\"]+)\"", text)
    if match:
        return float(match.group(1)), float(match.group(2))
    return 1000.0, 700.0


def _cell_geometry(svg: Path) -> tuple[float, float, float, float]:
    width, height = _svg_size(svg)
    ratio = width / height
    if ratio >= 1.35:
        w, h = 1120.0, max(420.0, min(820.0, 1120.0 / ratio))
    elif ratio <= 0.75:
        h, w = 980.0, max(420.0, min(820.0, 980.0 * ratio))
    else:
        w, h = 920.0, max(520.0, min(820.0, 920.0 / ratio))
    return 40.0, 40.0, round(w, 2), round(h, 2)


def _source_path(source: Path) -> str:
    return Path("..") / source.name


def _style(image_data: str, source: Path, source_format: str, source_hash: str, title: str) -> str:
    return (
        "shape=image;html=1;image=data:image/svg+xml;base64,"
        f"{image_data};sourcePath={html.escape(str(_source_path(source)), quote=True)};"
        f"sourceFormat={source_format};sourceHash={source_hash};"
        f"description={html.escape(title, quote=True)}"
    )


def _build_xml(source: Path, svg: Path) -> bytes:
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    source_format = "plantuml" if source.suffix == ".puml" else "mermaid"
    title = TITLE_BY_BASE.get(svg.stem, svg.stem)
    image_data = base64.b64encode(svg.read_bytes()).decode("ascii")
    x, y, w, h = _cell_geometry(svg)
    modified = datetime.now(timezone.utc).isoformat(timespec="seconds")

    root = ET.Element(
        "mxfile",
        {
            "host": "app.diagrams.net",
            "modified": modified,
            "agent": "make_drawio.py",
            "version": "24.7.17",
            "type": "device",
        },
    )
    diagram = ET.SubElement(root, "diagram", {"id": source.stem, "name": title})
    graph = ET.SubElement(
        diagram,
        "mxGraphModel",
        {
            "dx": "1400",
            "dy": "900",
            "grid": "1",
            "gridSize": "10",
            "guides": "1",
            "tooltips": "1",
            "connect": "1",
            "arrows": "1",
            "fold": "1",
            "page": "1",
            "pageScale": "1",
            "pageWidth": "1400",
            "pageHeight": "1000",
            "math": "0",
            "shadow": "0",
        },
    )
    root_cell = ET.SubElement(graph, "root")
    ET.SubElement(root_cell, "mxCell", {"id": "0"})
    ET.SubElement(root_cell, "mxCell", {"id": "1", "parent": "0"})

    image_cell = ET.SubElement(
        root_cell,
        "mxCell",
        {
            "id": "2",
            "value": "",
            "style": _style(image_data, source, source_format, source_hash, title),
            "vertex": "1",
            "parent": "1",
            "sourcePath": str(_source_path(source)),
            "sourceFormat": source_format,
            "sourceHash": source_hash,
            "description": title,
        },
    )
    geometry = ET.SubElement(image_cell, "mxGeometry", {"x": str(x), "y": str(y), "width": str(w), "height": str(h), "as": "geometry"})
    ET.SubElement(geometry, "mxRectangle", {"x": str(x), "y": str(y), "width": str(w), "height": str(h), "as": "alternateBounds"})

    source_text = source.read_text(encoding="utf-8")
    source_cell = ET.SubElement(
        root_cell,
        "mxCell",
        {
            "id": "3",
            "value": "&lt;pre&gt;" + html.escape(source_text) + "&lt;/pre&gt;",
            "style": "text;html=1;resizable=0;points=[];autosize=1;align=left;verticalAlign=top;spacingTop=-4;visible=0;",
            "vertex": "1",
            "parent": "1",
        },
    )
    source_geometry = ET.SubElement(source_cell, "mxGeometry", {"x": "40", "y": "40", "width": "10", "height": "10", "as": "geometry"})
    ET.SubElement(source_geometry, "mxRectangle", {"x": "40", "y": "40", "width": "10", "height": "10", "as": "alternateBounds"})

    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sources = sorted([*HERE.glob("*.mmd"), *HERE.glob("*.puml")])
    if len(sources) != 23:
        raise SystemExit(f"expected 23 sources, found {len(sources)}")
    for source in sources:
        svg = RENDERED / f"{source.stem}.svg"
        if not svg.exists():
            raise SystemExit(f"missing rendered SVG: {svg}")
        target = OUT / f"{source.stem}.drawio"
        target.write_bytes(_build_xml(source, svg))
        print(f"wrote: {target}")


if __name__ == "__main__":
    main()
