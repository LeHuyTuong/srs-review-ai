"""/diagram — the sds-reviewer vision chains served over HTTP.

Test levels (testing-strategy): the pipeline is exercised through the mock
provider (L3, no quota); prompt discipline (two-call order, describe JSON
reaches the judge) through a recording fake; cache-key and validation
contracts directly. The real end-to-end call is one deliberate smoke test,
skipped unless SRS_LIVE_VISION=1, mirroring the repo's live-gate pattern.
"""

from __future__ import annotations

import base64
import json
import os
import struct
import zlib

import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.diagram import ID_FAMILY_BY_TYPE, DiagramDescribe, DiagramVerdict
from app.llm.base import LlmError
from app.main import _diagram_cache, _limiter, app

PNG_A = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"  # distinct payloads...
PNG_B = "iVBORw0KGgoAAAAAAANSUhEUgAAAAEAAAAB"  # ...same shape, different bytes


@pytest.fixture(autouse=True)
def _isolate_state():
    _diagram_cache.clear()
    _limiter.reset()
    yield
    _diagram_cache.clear()
    _limiter.reset()


@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _req(**over):
    body = {
        "page_index": 7,
        "diagram_type": "erd",
        "context_text": "Table Customer has columns id, email. Table Order references Customer.",
        "image_b64": PNG_A,
    }
    body.update(over)
    return body


class RecordingProvider:
    """Captures the exact provider calls the endpoint makes."""

    name = "recording"
    model_id = "recording-v1"

    def __init__(self):
        self.calls: list[dict] = []

    async def generate_json(self, *, system, user, schema, image_b64=None):
        kind = (
            "describe"
            if "elements" in schema.get("properties", {})
            else "judge"
            if "clean" in schema.get("properties", {})
            else "other"
        )
        self.calls.append({"kind": kind, "system": system, "user": user, "image": image_b64})
        if kind == "describe":
            return (
                {
                    "elements": ["Customer", "Order"],
                    "relations": [
                        {"from": "Customer", "to": "Order", "label": "places", "arrowhead_side": "to"}
                    ],
                    "unreadable": ["tiny crow's foot near Order.id"],
                },
                self.model_id,
            )
        return (
            {
                "clean": False,
                "findings": [
                    {
                        "family": "UC",
                        "entity": "Order.id",
                        "evidence": "cot _id khong co nhan FK",
                        "severity": "red",
                    }
                ],
            },
            self.model_id,
        )


class EmptyInventoryProvider(RecordingProvider):
    """The measured 2026-09-14 failure mode: a page whose text NAMES
    diagrams but DRAWS none — describe comes back with no inventory,
    yet the judge still finds (document-level) problems."""

    async def generate_json(self, *, system, user, schema, image_b64=None):
        if "elements" in schema.get("properties", {}):
            return {"elements": [], "relations": [], "unreadable": []}, self.model_id
        return (
            {
                "clean": False,
                "findings": [
                    {
                        "family": "ERD",
                        "entity": "Table 105",
                        "evidence": "ten bang thieu tien to <Fields>",
                        "severity": "amber",
                    }
                ],
            },
            self.model_id,
        )


def test_empty_inventory_findings_are_bound_to_doc_not_requested_type(client, monkeypatch):
    """Family honesty: findings from a page with no drawn inventory must
    land under DOC even when the request asked for 'erd' — filing a table
    naming issue as an ERD defect misattributes the artifact at fault."""
    _patch_provider(monkeypatch, EmptyInventoryProvider())
    r = client.post("/diagram", json=_req(diagram_type="erd"))
    assert r.status_code == 200
    assert all(f["family"] == "DOC" for f in r.json()["verdict"]["findings"])


def test_nonempty_inventory_still_binds_to_requested_type(client, monkeypatch):
    """The override is narrow: a page that DID draw inventory keeps the
    requested-type family, where the judge's whims are still corrected."""
    _patch_provider(monkeypatch, RecordingProvider())
    r = client.post("/diagram", json=_req(diagram_type="erd"))
    assert r.status_code == 200
    assert all(f["family"] == "ERD" for f in r.json()["verdict"]["findings"])


def _patch_provider(monkeypatch, provider):
    import app.main as main

    monkeypatch.setattr(main, "build_provider", lambda settings: provider)


class TestPipeline:
    def test_mock_two_call_audit_returns_structured_ledger_material(self, client):
        first = client.post("/diagram", json=_req())
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["describe"]["elements"]  # mock reads names from context
        assert body["verdict"]["findings"]  # mock flags unknown arrowheads
        # ERD page -> findings bound to ERD family no matter what the judge said
        assert all(f["family"] == "ERD" for f in body["verdict"]["findings"])
        assert body["cached"] is False and body["mock"] is True

        second = client.post("/diagram", json=_req())
        assert second.json()["cached"] is True

    def test_describe_then_judge_order_judge_sees_describe_json_and_image(self, client, monkeypatch):
        provider = RecordingProvider()
        _patch_provider(monkeypatch, provider)
        r = client.post("/diagram", json=_req())
        assert r.status_code == 200, r.text
        kinds = [c["kind"] for c in provider.calls]
        assert kinds == ["describe", "judge"]
        # the two-call discipline: verdicts only exist in the second call,
        # and it receives BOTH the description and the image (trap #2).
        assert "places" not in provider.calls[0]["system"]
        judge = provider.calls[1]
        assert json.loads(judge["user"].split("\n", 1)[1])["elements"] == ["Customer", "Order"]
        assert judge["image"] == PNG_A
        assert provider.calls[0]["image"] == PNG_A
        # wrong-family finding from the judge is rewritten to the page family
        assert all(f["family"] == "ERD" for f in r.json()["verdict"]["findings"])

    def test_image_is_part_of_cache_identity(self, client):
        assert client.post("/diagram", json=_req()).json()["cached"] is False
        assert client.post("/diagram", json=_req()).json()["cached"] is True
        # same page/type/context, different image -> NOT a cache hit
        # (c3fc786 regression family: prompt inputs must be key inputs)
        assert client.post("/diagram", json=_req(image_b64=PNG_B)).json()["cached"] is False

    def test_diagram_type_and_context_reach_the_prompt_and_the_key(self, client):
        base = _req(diagram_type="sequence", context_text="Lifeline Auth issues token.")
        assert client.post("/diagram", json=base).json()["cached"] is False
        # identical request hits
        assert client.post("/diagram", json=base).json()["cached"] is True
        # context change misses
        changed = _req(diagram_type="sequence", context_text="Different page.")
        assert client.post("/diagram", json=changed).json()["cached"] is False

    def test_rate_limiter_charges_one_unit_per_two_call_audit(self, client, monkeypatch):
        monkeypatch.setenv("SRS_RATE_LIMIT_PER_DAY", "1")
        fresh = Settings(mock_mode=True, gemini_api_key="", rate_limit_per_day=1)
        app.dependency_overrides[get_settings] = lambda: fresh
        assert client.post("/diagram", json=_req()).status_code == 200
        _diagram_cache.clear()  # force past the cache to reach the limiter
        blocked = client.post("/diagram", json=_req(page_index=8))
        assert blocked.status_code == 429
        assert blocked.headers.get("retry-after")


class TestContract:
    def test_unknown_diagram_type_rejected(self, client):
        assert client.post("/diagram", json=_req(diagram_type="pie_chart")).status_code == 422

    def test_empty_image_rejected(self, client):
        assert client.post("/diagram", json=_req(image_b64="")).status_code == 422

    def test_context_is_truncated_not_rejected(self, client):
        r = client.post("/diagram", json=_req(context_text="x" * 50_000))
        assert r.status_code == 200

    def test_provider_failure_maps_to_502_not_500(self, client, monkeypatch):
        class Broken:
            name = "broken"

            async def generate_json(self, **kwargs):
                raise LlmError("boom", retryable=False)

        _patch_provider(monkeypatch, Broken())
        assert client.post("/diagram", json=_req()).status_code == 502

    def test_judge_garbage_maps_to_502(self, client, monkeypatch):
        class GarbageJudge(RecordingProvider):
            async def generate_json(self, *, system, user, schema, image_b64=None):
                if "elements" in schema.get("properties", {}):
                    return await super().generate_json(
                        system=system, user=user, schema=schema, image_b64=image_b64
                    )
                return {"clean": "yes-please", "findings": []}, "garbage"

        _patch_provider(monkeypatch, GarbageJudge())
        assert client.post("/diagram", json=_req()).status_code == 502


class TestPureLogic:
    def test_bind_family_rewrites_foreign_families(self):
        v = DiagramVerdict.model_validate(
            {
                "clean": False,
                "findings": [{"family": "UC", "entity": "e", "evidence": "x", "severity": "amber"}],
            }
        )
        bound = v.bind_family("ERD")
        assert bound.findings[0].family == "ERD"
        assert v.findings[0].family == "UC"  # original untouched

    def test_describe_stringifies_odd_items_instead_of_failing(self):
        d = DiagramDescribe.model_validate(
            {"elements": ["Customer", 3, {"k": "v"}], "relations": [], "unreadable": None}
        )
        assert d.elements[1] == "3"
        assert '"k": "v"' in d.elements[2]
        assert d.unreadable == []

    def test_every_diagram_type_has_an_id_family(self):
        assert set(ID_FAMILY_BY_TYPE) == {
            "erd",
            "state_machine",
            "sequence",
            "class",
            "use_case",
            "component",
            "unknown",
        }


def _valid_png_b64() -> str:
    """A real 1x1 PNG, built not typed — a hand-typed base64 blob failed the
    live API with a corrupt-image 502, which is exactly the kind of fixture
    bug a live smoke test exists to catch (in the fixture, not the wire)."""

    def chunk(t: bytes, d: bytes) -> bytes:
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))

    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
    png = b"\x89PNG\r\n\x1a\n" + ihdr + idat + chunk(b"IEND", b"")
    return base64.b64encode(png).decode()


@pytest.mark.skipif(
    os.environ.get("SRS_LIVE_VISION") != "1",
    reason="real quota call — opt in with SRS_LIVE_VISION=1",
)
def test_live_smoke_describes_a_real_image():
    """L4: one real two-call audit. Run deliberately, not in CI."""
    from app.config import Settings as S

    settings = S()  # reads .env through the normal path
    assert settings.has_llm_credentials, "live test needs GEMINI_API_KEY"
    app.dependency_overrides[get_settings] = lambda: settings
    with TestClient(app) as live:
        # 1x1 image: describe must report NOTHING, judge must not invent
        r = live.post(
            "/diagram",
            json={
                "page_index": 0,
                "diagram_type": "unknown",
                "context_text": "single pixel test fixture",
                "image_b64": _valid_png_b64(),
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["mock"] is False
        assert body["model"] != "mock-rules-v1"
        # the anti-trap-#3 property, on the real model: an image with no
        # diagram yields an empty inventory and an honest verdict, not
        # hallucinated ERD findings.
        assert body["describe"]["elements"] == []
        assert body["describe"]["relations"] == []
        assert isinstance(body["verdict"]["clean"], bool)
    app.dependency_overrides.clear()
