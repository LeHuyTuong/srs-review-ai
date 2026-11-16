"""Deterministic review of a draw.io Use Case diagram (``.drawio`` XML).

Runs the vendored ``uc-review.mjs`` (server/vendor/uc-review/) in a temp dir —
the same engine startup-srs uses — and returns what the tool wrote for the
reader: title, counts, and per finding a number, a severity, what is wrong and
how to fix it, plus the tool's ``.review.drawio`` with numbered marks on the
diagram itself.

No LLM call: the same file always yields the same findings, it costs no
provider quota, and nothing leaves the server. Internal rule ids of the tool
are deliberately NOT returned (only its reader-facing text).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

VENDORED_SCRIPT = Path(__file__).resolve().parents[2] / "vendor" / "uc-review" / "uc-review.mjs"
MAX_XML_CHARS = 2_000_000
TIMEOUT_S = 60
_DRAWIO = re.compile(r"<mxfile\b|<mxGraphModel\b")


class DrawioReviewError(Exception):
    """A reader-safe message plus the HTTP status the route should answer."""

    def __init__(self, message: str, status: int) -> None:
        super().__init__(message)
        self.message = message
        self.status = status


@dataclass
class DrawioFinding:
    num: int
    severity: str  # "error" | "review"
    what: str
    fix: str


@dataclass
class DrawioReview:
    title: str
    error_count: int
    review_count: int
    findings: list[DrawioFinding] = field(default_factory=list)
    read_note: str | None = None
    reviewed_xml: str = ""
    actors: int = 0
    use_cases: int = 0


def script_path() -> Path:
    override = os.environ.get("UC_REVIEW_SCRIPT", "").strip()
    return Path(override) if override else VENDORED_SCRIPT


def node_binary() -> str | None:
    return os.environ.get("UC_REVIEW_NODE", "").strip() or shutil.which("node")


def check_xml(xml: str) -> str:
    if not xml.strip():
        raise DrawioReviewError("Chưa có sơ đồ để kiểm.", 400)
    if len(xml) > MAX_XML_CHARS:
        raise DrawioReviewError("Sơ đồ quá lớn (tối đa khoảng 2 MB).", 413)
    if not _DRAWIO.search(xml):
        raise DrawioReviewError("Đây không phải tệp .drawio (không thấy mxfile / mxGraphModel).", 400)
    return xml


def _text(v: Any) -> str:
    return v if isinstance(v, str) else ""


def parse_outputs(web: dict[str, Any], model: dict[str, Any], reviewed_xml: str) -> DrawioReview:
    counts = web.get("counts") or {}
    findings = []
    for item in web.get("items") or []:
        if not isinstance(item, dict):
            continue
        try:
            num = int(item.get("num"))
        except (TypeError, ValueError):
            continue
        findings.append(
            DrawioFinding(
                num=num,
                severity="error" if item.get("sev") == "error" else "review",
                what=_text(item.get("what")),
                fix=_text(item.get("fix")),
            )
        )
    return DrawioReview(
        title=_text(web.get("title")),
        error_count=int(counts.get("error") or 0),
        review_count=int(counts.get("review") or 0),
        findings=findings,
        read_note=_text(web.get("readNote")) or None,
        reviewed_xml=reviewed_xml,
        actors=len(model.get("actors") or []),
        use_cases=len(model.get("usecases") or []),
    )


def review_drawio(xml: str, lang: str = "vi") -> DrawioReview:
    """Run the tool on *xml*. Raises DrawioReviewError with a reader-safe message."""
    check_xml(xml)
    script = script_path()
    node = node_binary()
    if node is None or not script.is_file():
        raise DrawioReviewError("Máy chủ chưa cài công cụ kiểm sơ đồ (Node / uc-review.mjs).", 503)

    with tempfile.TemporaryDirectory(prefix="drawio-review-") as tmp:
        work = Path(tmp)
        source = work / "so-do.drawio"
        out = work / "out"
        source.write_text(xml, encoding="utf-8")
        env = {k: v for k, v in os.environ.items() if k != "UC_REVIEW_ASK"}  # never let the tool call an AI
        try:
            proc = subprocess.run(  # noqa: S603 — argv list, no shell; args are server-made paths, user XML only in the temp file
                [
                    node,
                    str(script),
                    "review",
                    str(source),
                    "--mode",
                    "errors",
                    "--no-png",
                    "--web",
                    "--out-dir",
                    str(out),
                    "--lang",
                    lang,
                ],
                cwd=work,
                env=env,
                capture_output=True,
                text=True,
                timeout=TIMEOUT_S,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise DrawioReviewError(
                f"Kiểm quá {TIMEOUT_S} giây nên đã dừng — sơ đồ có thể quá lớn.", 504
            ) from exc

        if proc.returncode != 0:
            if "mxGraphModel" in (proc.stderr or ""):
                raise DrawioReviewError("Tệp không có trang sơ đồ nào (mxGraphModel).", 422)
            raise DrawioReviewError(
                "Công cụ không đọc được sơ đồ này. Mở bằng draw.io, lưu lại rồi kiểm lại.", 422
            )
        try:
            model = json.loads((out / "so-do.model.json").read_text(encoding="utf-8"))
            web = json.loads((out / "so-do.web.json").read_text(encoding="utf-8"))
            reviewed = (out / "so-do.review.drawio").read_text(encoding="utf-8")
        except (OSError, json.JSONDecodeError) as exc:
            raise DrawioReviewError("Công cụ kiểm không trả đủ kết quả. Thử lại sau.", 502) from exc

    result = parse_outputs(web, model, reviewed)
    if result.actors == 0 and result.use_cases == 0:
        raise DrawioReviewError("Không thấy actor hay use case nào. Hiện chỉ kiểm được sơ đồ Use Case.", 422)
    return result
