"""Offline provider — the demo safety net (research 05 day 3, AC4).

It is deliberately deterministic and rule-driven rather than a canned blob, so
the whole pipeline (schema validation + quote verification) still runs. Quotes
are cut from the real input text, which means they always verify as `exact`.
"""

from __future__ import annotations

import re
from typing import Any

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
    ) -> tuple[dict[str, Any], str]:
        if "grounded" in schema.get("properties", {}):
            return self._ask(user), self.model_id
        return self._review(user), self.model_id

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
