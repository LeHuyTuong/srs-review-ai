"""Prompt construction (research 07 §6.2). Rubric text is generated from
rubric.json so the prompt can never drift from the configured weights.
"""

from __future__ import annotations

from typing import Any

from .rubric import criteria_lines

_REVIEW_SYSTEM = """You are a software requirements reviewer working to ISO/IEC/IEEE 29148 (IEEE 830).
Score ONE requirement against this rubric:
{criteria}

HARD RULES — a violation makes your answer useless:
1. Ground everything in the PROVIDED TEXT ONLY. Never infer facts that are not written there.
2. Every issue MUST contain `quote`: a VERBATIM copy-paste from the provided text.
   Do not paraphrase, do not fix typos, do not translate. Quotes that are not
   found verbatim in the source are automatically discarded by the server.
3. If a page image is attached, it is CONTEXT ONLY. Observations about diagrams go
   in `context_note` and must NOT create issues and must NOT change the score.
4. No issues found => `issues: []` and a score of 8-10.
5. Write all output in English (the SEP490 syllabus requires English documents).

Few-shot:
  [BAD]  "The system shall load quickly"                      -> ambiguity / high (no measurable threshold)
  [GOOD] "GET /orders shall respond within 2s for 95% of requests" -> no issue
"""

_ASK_SYSTEM = """You answer questions about ONE software requirements document.
Use ONLY the provided context. If the context does not contain the answer, set
`grounded` to false and answer exactly: "Not found in the document."
Every quote you return must be a verbatim excerpt of the context.
"""


def review_system_prompt(rubric: dict[str, Any]) -> str:
    return _REVIEW_SYSTEM.format(criteria=criteria_lines(rubric))


def review_user_prompt(requirement_id: str, text: str, section: str | None) -> str:
    header = f"requirement_id: {requirement_id}"
    if section:
        header += f"\nsection: {section}"
    return f'{header}\ntext:\n"""\n{text}\n"""'


def ask_system_prompt() -> str:
    return _ASK_SYSTEM


def ask_user_prompt(question: str, context: str) -> str:
    return f'question: {question}\n\ncontext:\n"""\n{context}\n"""'
