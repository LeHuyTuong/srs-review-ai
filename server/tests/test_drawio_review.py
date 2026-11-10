"""/diagram/drawio — deterministic Use Case review of a .drawio file.

The engine is the vendored uc-review.mjs run in a subprocess. Tests that need
it run for real (no fake of the tool: the value of this endpoint IS the tool's
verdict) and skip when Node is absent; the guards in front of the tool and the
output parsing are tested without Node.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.infrastructure import drawio_review
from app.infrastructure.drawio_review import DrawioReviewError, check_xml, parse_outputs
from app.main import app

FIXTURES = Path(__file__).parent / "fixtures"
FIXTURE = FIXTURES / "use-case-admin.drawio"  # real shapes: 1 actor, 9 use cases
EMBEDDED_SVG = FIXTURES / "use-case-embedded-svg.drawio"  # docs/diagrams/uml25 style: one SVG image
needs_node = pytest.mark.skipif(
    drawio_review.node_binary() is None or not drawio_review.script_path().is_file(),
    reason="Node or vendored uc-review.mjs not available",
)


@pytest.fixture
def client():
    return TestClient(app)


# ---- guards (no Node needed) ----


@pytest.mark.parametrize(
    ("xml", "status"),
    [
        ("   ", 400),
        ("<html><body>not a diagram</body></html>", 400),
        ("<mxfile>" + "x" * drawio_review.MAX_XML_CHARS, 413),
    ],
)
def test_check_xml_rejects_before_running_the_tool(xml, status):
    with pytest.raises(DrawioReviewError) as err:
        check_xml(xml)
    assert err.value.status == status


def test_route_answers_400_for_a_non_drawio_body(client):
    r = client.post("/diagram/drawio", json={"xml": "<svg></svg>"})
    assert r.status_code == 400
    assert "không phải tệp .drawio" in r.json()["detail"]


def test_route_rejects_unknown_fields(client):
    r = client.post("/diagram/drawio", json={"xml": "<mxfile/>", "model": "gemini"})
    assert r.status_code == 422


def test_missing_tool_is_a_503_not_a_crash(client, monkeypatch):
    monkeypatch.setenv("UC_REVIEW_SCRIPT", "/nonexistent/uc-review.mjs")
    r = client.post("/diagram/drawio", json={"xml": FIXTURE.read_text(encoding="utf-8")})
    assert r.status_code == 503
    assert "chưa cài công cụ" in r.json()["detail"]


def test_parse_outputs_keeps_reader_text_and_drops_internal_ids():
    web = {
        "title": "Kết quả kiểm tra: 1 lỗi, 1 chỗ nên xem lại",
        "counts": {"error": 1, "review": 1},
        "readNote": "",
        "items": [
            {
                "num": 1,
                "sev": "error",
                "what": "Thiếu khung hệ thống.",
                "fix": "Vẽ khung.",
                "rule": "UC-L0-7",
            },
            {"num": 2, "sev": "warn", "what": "Tên use case nên là động từ.", "fix": "Đổi tên."},
            {"num": "x", "sev": "error", "what": "bỏ qua", "fix": ""},
        ],
    }
    result = parse_outputs(web, {"actors": [1], "usecases": [1, 2]}, "<mxfile/>")
    assert [f.num for f in result.findings] == [1, 2]
    assert result.findings[1].severity == "review"  # anything not "error" is review
    assert not hasattr(result.findings[0], "rule")
    assert result.read_note is None
    assert (result.actors, result.use_cases) == (1, 2)


# ---- real tool run ----


@needs_node
def test_real_use_case_diagram_gets_the_tools_findings_and_a_marked_copy(client):
    xml = FIXTURE.read_text(encoding="utf-8")
    r = client.post("/diagram/drawio", json={"xml": xml, "file_name": "uc.drawio"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["engine"] == "uc-review" and body["deterministic"] is True
    assert body["actors"] > 0 and body["use_cases"] > 0
    assert (body["actors"], body["use_cases"]) == (1, 9)
    whats = [f["what"] for f in body["findings"]]
    assert 'Actor "Admin" nối 9/9 use case.' in whats
    assert body["error_count"] == sum(f["severity"] == "error" for f in body["findings"])
    assert "<mxfile" in body["reviewed_xml"] or "<mxGraphModel" in body["reviewed_xml"]
    assert body["reviewed_xml"] != xml  # marks were added


@needs_node
def test_same_file_twice_gives_the_same_findings(client):
    xml = FIXTURE.read_text(encoding="utf-8")
    a = client.post("/diagram/drawio", json={"xml": xml}).json()
    b = client.post("/diagram/drawio", json={"xml": xml}).json()
    assert a["findings"] == b["findings"]


@needs_node
def test_a_drawio_that_is_only_an_embedded_image_is_a_422_not_a_clean_pass(client):
    """The repo's own docs/diagrams/uml25 files are one SVG image inside .drawio:
    there is nothing to read, and "0 findings" would be a lie."""
    r = client.post("/diagram/drawio", json={"xml": EMBEDDED_SVG.read_text(encoding="utf-8")})
    assert r.status_code == 422
    assert "Use Case" in r.json()["detail"]


@needs_node
def test_a_drawio_without_actors_or_use_cases_is_a_422(client):
    xml = (
        '<mxfile><diagram name="P1"><mxGraphModel><root><mxCell id="0"/>'
        '<mxCell id="1" parent="0"/>'
        '<mxCell id="2" value="Box" style="rounded=0;" vertex="1" parent="1">'
        '<mxGeometry x="10" y="10" width="80" height="40" as="geometry"/></mxCell>'
        "</root></mxGraphModel></diagram></mxfile>"
    )
    r = client.post("/diagram/drawio", json={"xml": xml})
    assert r.status_code == 422
    assert "Use Case" in r.json()["detail"]


def test_tool_is_never_handed_the_ai_switch(monkeypatch, tmp_path):
    """UC_REVIEW_ASK would let the tool call an AI model; the server strips it."""
    seen = {}

    def fake_run(cmd, **kwargs):
        seen["env"] = kwargs["env"]
        raise drawio_review.subprocess.TimeoutExpired(cmd, 1)

    monkeypatch.setenv("UC_REVIEW_ASK", "1")
    monkeypatch.setenv("UC_REVIEW_NODE", "/usr/bin/true")
    script = tmp_path / "uc-review.mjs"
    script.write_text("", encoding="utf-8")
    monkeypatch.setenv("UC_REVIEW_SCRIPT", str(script))
    monkeypatch.setattr(drawio_review.subprocess, "run", fake_run)
    with pytest.raises(DrawioReviewError) as err:
        drawio_review.review_drawio(FIXTURE.read_text(encoding="utf-8"))
    assert err.value.status == 504
    assert "UC_REVIEW_ASK" not in seen["env"]
