"""Offline provider — the demo safety net (research 05 day 3, AC4).

It is deliberately deterministic and rule-driven rather than a canned blob, so
the whole pipeline (schema validation + quote verification) still runs. Quotes
are cut from the real input text, which means they always verify as `exact`.
"""

from __future__ import annotations

import json
import re
from typing import Any

from .base import GenerateJsonResult

VAGUE_TERMS = (
    "quickly",
    "fast",
    "user-friendly",
    "friendly",
    "easy to use",
    "efficient",
    "as soon as possible",
    "appropriate",
    "etc.",
    "flexible",
    "robust",
    "nhanh",
    "thân thiện",
    "dễ dùng",
    "hợp lý",
)

# A sentence is a run of non-terminator characters, optionally closed by one
# terminator. The `(?<=\d)\.(?=\d)` alternative keeps a dot that sits between
# digits inside the run, so an SRS section number ("3.2 Payment.") or a
# threshold ("1.5s") is not sliced in half. Without it the quote for
# "3.2 Payment." came out as "2 Payment." — still verifiable, but it reads like
# a parser bug in front of the examiners.
_SENTENCE = re.compile(r"(?:[^.!?\n]|(?<=\d)\.(?=\d))+[.!?]?")

# Must match prompt.BATCH_UNIT_MARKER — the offline provider reads back the
# prompt it was handed, the same way a real model reads its input.
_UNIT_MARKER = re.compile(r"^--- unit_index:\s*(\d+)\s*$", re.MULTILINE)


class MockProvider:
    name = "mock"
    model_id = "mock-rules-v1"

    async def generate_json(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        image_b64: str | None = None,
    ) -> GenerateJsonResult:
        props = schema.get("properties", {})
        prompt_tok = max(10, (len(system) + len(user)) // 4)
        comp_tok = 60
        usage = {
            "prompt_tokens": prompt_tok,
            "completion_tokens": comp_tok,
            "total_tokens": prompt_tok + comp_tok,
        }
        if "grounded" in props:
            return GenerateJsonResult(self._ask(user), self.model_id, usage)
        if "elements" in props:
            return GenerateJsonResult(self._describe(user), self.model_id, usage)
        if "clean" in props:
            return GenerateJsonResult(self._judge(user), self.model_id, usage)
        if "results" in props:
            return GenerateJsonResult(self._review_batch(user), self.model_id, usage)
        return GenerateJsonResult(self._review(user), self.model_id, usage)

    # ------------------------------------------------------------------
    def _review(self, user: str) -> dict[str, Any]:
        requirement_id = _field(user, "requirement_id") or "UNKNOWN"
        text = _quoted_block(user)
        issues: list[dict[str, Any]] = []

        for sentence in (s.strip() for s in _SENTENCE.findall(text)):
            if not sentence:
                continue
            lowered = sentence.lower()
            hit = next((term for term in VAGUE_TERMS if term in lowered), None)
            if hit:
                issues.append(
                    {
                        "type": "ambiguity",
                        "severity": "high",
                        "quote": sentence,
                        "suggestion": (
                            f"'{hit}' is not measurable. Replace it with a threshold that a "
                            "tester can verify, e.g. 'within 2s for 95% of requests'."
                        ),
                    }
                )
            elif not re.search(r"\b(shall|must)\b", lowered):
                issues.append(
                    {
                        "type": "untestable",
                        "severity": "medium",
                        "quote": sentence,
                        "suggestion": (
                            "State the requirement with 'shall' and a verifiable acceptance "
                            "criterion so it can be tested."
                        ),
                    }
                )

        issues = issues[:3]
        score = 9 if not issues else max(3, 9 - 2 * len(issues))
        result: dict[str, Any] = {
            "requirement_id": requirement_id,
            "score": score,
            "issues": issues,
        }
        if image_context := _field(user, "section"):
            result["context_note"] = f"Offline mode: no diagram analysis for section {image_context}."
        return result

    def _review_batch(self, user: str) -> dict[str, Any]:
        """Offline batch review: the same rules, once per numbered block.

        This is what keeps mock mode (and every test that runs against it) on the
        real batch code path instead of a bespoke shortcut — the endpoint, the
        split-on-failure logic and the per-unit cache all get exercised.
        """
        markers = list(_UNIT_MARKER.finditer(user))
        results: list[dict[str, Any]] = []
        for position, marker in enumerate(markers):
            end = markers[position + 1].start() if position + 1 < len(markers) else len(user)
            block = user[marker.end() : end]
            reviewed = self._review(block)
            # The marker owns the index; the block's own text cannot invent one.
            reviewed["unit_index"] = int(marker.group(1))
            results.append(reviewed)
        return {"results": results}

    def _describe(self, user: str) -> dict[str, Any]:
        """Offline diagram "reading": deterministic inventory of names in the
        page context, zero elements when there is nothing to read. Rule-driven
        like _review, so the two-call pipeline still exercises real parsing."""
        context = _quoted_block(user)
        names: list[str] = []
        for token in re.findall(r"[A-Z][A-Za-z0-9_]{3,}", context):
            if token not in names:
                names.append(token)
        return {
            "elements": names[:8],
            "relations": [
                {"from": a, "to": b, "label": "", "arrowhead_side": "unknown"}
                # strict=False is the point: names[1:] is always one shorter —
                # this is an adjacent-pair walk, not a mis-zip.
                for a, b in zip(names, names[1:], strict=False)
            ][:4],
            "unreadable": ["toan bo trang"] if not names else [],
        }

    def _judge(self, user: str) -> dict[str, Any]:
        """Deterministic judge over the describe JSON embedded in the prompt:
        unknown arrowhead sides are the skill's cardinality red flag; an
        inventory with nothing readable is an amber "cannot assess". Family
        is left to "DOC" — the endpoint bind_family() rewrites it per page."""
        start, end = user.find("{"), user.rfind("}")
        try:
            describe = json.loads(user[start : end + 1])
        except ValueError:
            describe = {}
        findings: list[dict[str, Any]] = []
        relations = describe.get("relations") or []
        for rel in relations:
            if rel.get("arrowhead_side", "unknown") == "unknown":
                findings.append(
                    {
                        "family": "DOC",
                        "entity": f"{rel.get('from', '?')}->{rel.get('to', '?')}",
                        "evidence": "chieu quan he khong xac dinh duoc tu mo ta",
                        "severity": "red",
                    }
                )
        if describe.get("unreadable"):
            findings.append(
                {
                    "family": "DOC",
                    "entity": "page",
                    "evidence": "mot phan chu khong doc duoc o do phan giai nay",
                    "severity": "amber",
                }
            )
        return {"clean": not findings, "findings": findings[:8]}

    def _ask(self, user: str) -> dict[str, Any]:
        question = _field(user, "question") or ""
        context = _quoted_block(user)
        keywords = [w for w in re.findall(r"[\w-]{4,}", question.lower())]
        hit = next((k for k in keywords if k in context.lower()), None)
        if hit is None:
            return {"answer": "Not found in the document.", "grounded": False, "quotes": []}
        sentence = next(
            (s.strip() for s in _SENTENCE.findall(context) if hit in s.lower()),
            "",
        )
        return {
            "answer": f"The document mentions '{hit}': {sentence}",
            "grounded": True,
            "quotes": [sentence] if sentence else [],
        }


def _field(blob: str, name: str) -> str | None:
    match = re.search(rf"^{re.escape(name)}:\s*(.+)$", blob, re.MULTILINE)
    return match.group(1).strip() if match else None


def _quoted_block(blob: str) -> str:
    match = re.search(r'"""(.*?)"""', blob, re.DOTALL)
    return match.group(1).strip() if match else blob
