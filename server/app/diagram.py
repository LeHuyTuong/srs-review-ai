"""Diagram audit — the sds-reviewer vision chains (skill steps 4–6).

Prompts are ported VERBATIM from ~/.dsh/skills/sds-reviewer/references/
vision-prompts.md (Vietnamese included — the model must read the same spec a
human reviewer follows). The skill's discipline, encoded here:

1. DESCRIBE and JUDGE are SEPARATE calls. In one call the model "đoán thay
   vì nhìn" (guesses instead of looks) — known trap #2 from the HisWise
   session. The judge call re-receives the image plus the describe JSON.
2. The describe prompt forbids verdicts ("Không kết luận đúng/sai") so the
   judge operates on an explicit inventory, not on vibes.
3. `unreadable` is a first-class field: an A4 page renders at ~1.9 dots/pt
   under the app's 1600px cap (measured, cdeb879) — so fine print genuinely
   may not resolve. Trap #3 ("model reads wrong then self-confirms") means
   red verdicts from tiny text are untrustworthy; the model is told to list
   them as unreadable instead of guessing.

Every value interpolated into these prompts (image, type, context) must be
in the cache key — the c3fc786 rule. diagram_cache_key() below is the only
place that fingerprint is built.
"""

from __future__ import annotations

import json
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field, field_validator

from .cache import cache_key
from .schemas import Strict

#: Diagram prompts version — bumped independently of the review prompt
#: version; both go into the cache key (diagram_cache_key).
#: d2 (2026-09-21): ACTIVITY type + judge question added (policy §9).
DIAGRAM_PROMPT_VERSION = "d2"


class DiagramType(StrEnum):
    """Rubric mục D ID families that vision can judge per page."""

    ERD = "erd"
    STATE_MACHINE = "state_machine"
    SEQUENCE = "sequence"
    CLASS = "class"
    USE_CASE = "use_case"
    COMPONENT = "component"
    ACTIVITY = "activity"
    UNKNOWN = "unknown"


#: Ledger ID prefixes per rubric mục D (ERD-01, SEQ-CLS-01, ...). The client
#: owns numbering stability; the server echoes the family back per finding.
ID_FAMILY_BY_TYPE: dict[DiagramType, str] = {
    DiagramType.ERD: "ERD",
    DiagramType.STATE_MACHINE: "SM",
    DiagramType.SEQUENCE: "SEQ-CLS",
    DiagramType.CLASS: "SEQ-CLS",
    DiagramType.USE_CASE: "UC",
    DiagramType.COMPONENT: "PKG",
    DiagramType.ACTIVITY: "ACT",
    DiagramType.UNKNOWN: "DOC",
}

# --- prompts ----------------------------------------------------------------

# The "prompt gốc" of vision-prompts.md, verbatim, plus the JSON contract
# the shared rule demands ("ép model trả về CẤU TRÚC để checker parse được").
DESCRIBE_SYSTEM = (
    "Bạn đang audit một mảnh diagram từ tài liệu SDS. Nhiệm vụ:\n"
    "1. Liệt kê MỌI phần tử nhìn thấy (tên nguyên văn, kể cả typo — ghi "
    "[sic] sau lỗi).\n"
    '2. Liệt kê MỌI quan hệ: "A -> B : nhãn (kiểu mũi tên, đầu nào có '
    "crow's foot)\".\n"
    "3. Không kết luận đúng/sai — chỉ mô tả. Model chấm lỗi là lượt gọi "
    "SAU.\n"
    "Phần chữ hay mũi tên không đọc được rõ ở độ phân giải này KHÔNG được "
    "đoán — đưa nguyên văn vào unreadable (bẫy đã biết: model đọc nhầm rồi "
    "tự tin).\n"
    'Trả về JSON: {"elements":[...],"relations":[{"from","to","label",'
    '"arrowhead_side"}],"unreadable":[...]}'
)

# Type-specific judge questions, verbatim from vision-prompts.md.
_JUDGE_QUESTIONS: dict[DiagramType, str] = {
    DiagramType.ERD: (
        "Với mỗi relation, xác định FK nằm phía nào (cột nào của bảng nào "
        "mang tên <B>_id). Vẽ đúng chiều 1-N chưa? Liệt kê: cột mang hậu tố "
        "_id mà KHÔNG có nhãn FK; cột PK/unique-về-nghiệp vụ (email, token, "
        "hash) mà KHÔNG có UNIQUE; cặp bảng có FK nhưng KHÔNG có đường nối."
    ),
    DiagramType.STATE_MACHINE: (
        "List mọi state name + mọi transition 'from -> to [event]'. Sau đó "
        "đối chiếu danh sách giá trị status được đưa ra (trích từ SQL trong "
        "sequences: SET status='X'): giá trị nào KHÔNG có state? state nào "
        "không có đường ra?"
    ),
    DiagramType.SEQUENCE: (
        "Mọi lifeline: tên nguyên văn + method gọi nó mang theo. Mọi giá trị "
        "enum xuất hiện trong note/message (status=..., confidence >= ...). "
        "Mọi alt/opt condition."
    ),
    DiagramType.CLASS: (
        "Mọi class + signature method ĐẦY ĐỦ tham số. Mọi quan hệ có "
        "multiplicity? Liệt kê class không có quan hệ nào (orphan)."
    ),
    DiagramType.USE_CASE: (
        "Mọi oval + tên + quan hệ với actor (đường liền hay đứt, đầu mũi "
        "tên phía nào, có stereotype <<include>>/<<extend>> không). Có "
        "initial/generalization arrow nào bị dùng thay include không?"
    ),
    DiagramType.COMPONENT: (
        "Mọi box + MỌI mũi tên: from→to, nhãn. Box nào không mũi tên nào "
        "(orphan)? Mũi tên nào đi qua vùng package khác?"
    ),
    # Ported from review-rules/references/uml25-diagram-policy.md §9 (2026-09-21).
    DiagramType.ACTIVITY: (
        "List mọi node: initial/final, action (cụm động từ như 'Validate "
        "payment', KHÔNG phải danh từ), decision với guard trên MỌI cạnh ra "
        "([yes]/[no] loại trừ nhau và đủ — guard chồng là red), fork/join có "
        "cân bằng không. Có cạnh treo hay action không đường vào không? "
        "Swimlane có đặt tên theo actor/component không? Và quan trọng nhất: "
        "đây có thật là Activity diagram không, hay là FLOWCHART (hình thoi "
        "ghi Yes/No ngoài ngoặc, hình bình hành I/O, hình trụ database) — "
        "flowchart là red (G6a)."
    ),
    DiagramType.UNKNOWN: (
        "Chỉ liệt kê các phần tử và quan hệ có thể đọc chắc chắn từ JSON mô "
        "tả; nếu JSON mô tả rỗng hoặc toàn unreadable, trả về findings rỗng "
        "và clean=false (không đánh giá được, không phải không có lỗi)."
    ),
}

_JUDGE_CONTRACT = (
    "\nMỗi lỗi tìm được là một finding: family = mã mục (ERD/SM/SEQ-CLS/UC/"
    "PKG/ACT/DOC), entity = tên nguyên văn trong JSON mô tả, evidence = câu mô "
    "tả lỗi bằng tiếng Việt ngắn gọn dựa TRÊN JSON mô tả + ảnh, severity = "
    "'red' (đảo cardinality, FK không đường nối, state không đường ra) hoặc "
    "'amber' (thiếu nhãn, nghi ngờ). Không bịa lỗi không thấy trong ảnh. "
    "'clean' = true khi KHÔNG có finding nào."
)


def describe_user_prompt(*, page_index: int, diagram_type: DiagramType, context_text: str) -> str:
    return (
        f"Trang {page_index + 1}. Loại diagram được detector gọi tên: "
        f"{diagram_type.value}. Ngữ cảnh chữ quanh trang:\n"
        f'"""\n{context_text}\n"""'
    )


def judge_system_prompt(diagram_type: DiagramType) -> str:
    return (
        "Bạn đang CHẤM MỘT mảnh diagram của tài liệu SDS, dựa trên JSON mô "
        "tả đã được lượt gọi trước đọc từ chính ảnh này (và ảnh gửi kèm "
        "lại). Nhiệm vụ:\n" + _JUDGE_QUESTIONS[diagram_type] + _JUDGE_CONTRACT
    )


def judge_user_prompt(describe: DiagramDescribe) -> str:
    return "JSON mô tả từ lượt gọi trước:\n" + json.dumps(describe.model_dump(), ensure_ascii=False, indent=1)


# --- LLM response schemas (Gemini protobuf casing — see schemas.py note) ---

LLM_DIAGRAM_DESCRIBE_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "elements": {"type": "ARRAY", "items": {"type": "STRING"}},
        "relations": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "from": {"type": "STRING"},
                    "to": {"type": "STRING"},
                    "label": {"type": "STRING"},
                    "arrowhead_side": {
                        "type": "STRING",
                        "enum": ["from", "to", "both", "none", "unknown"],
                    },
                },
                "required": ["from", "to"],
                "propertyOrdering": ["from", "to", "label", "arrowhead_side"],
            },
        },
        "unreadable": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["elements", "relations", "unreadable"],
    "propertyOrdering": ["elements", "relations", "unreadable"],
}

LLM_DIAGRAM_JUDGE_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "clean": {"type": "BOOLEAN"},
        "findings": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "family": {
                        "type": "STRING",
                        "enum": sorted(set(ID_FAMILY_BY_TYPE.values())),
                    },
                    "entity": {"type": "STRING"},
                    "evidence": {"type": "STRING"},
                    "severity": {"type": "STRING", "enum": ["red", "amber"]},
                },
                "required": ["family", "entity", "evidence", "severity"],
                "propertyOrdering": ["family", "entity", "severity", "evidence"],
            },
        },
    },
    "required": ["clean", "findings"],
    "propertyOrdering": ["clean", "findings"],
}


# --- wire models -------------------------------------------------------------


class DiagramRelation(Strict):
    model_config = {"populate_by_name": True}

    source: str = Field(alias="from")
    target: str = Field(alias="to")
    label: str = ""
    arrowhead_side: str = "unknown"


class DiagramDescribe(BaseModel):
    """Tolerant of extra keys a model may add; strict on the shape it promised."""

    elements: list[str] = Field(default_factory=list)
    relations: list[DiagramRelation] = Field(default_factory=list)
    unreadable: list[str] = Field(default_factory=list)

    @field_validator("elements", "unreadable", mode="before")
    @classmethod
    def _stringify_items(cls, v: Any) -> Any:
        # Models occasionally return nulls or non-strings; accept rather than
        # 502 the whole page over one number in an elements list.
        if v is None:
            return []
        if isinstance(v, list):
            return [x if isinstance(x, str) else json.dumps(x, ensure_ascii=False) for x in v]
        return v


class DiagramFinding(BaseModel):
    family: str
    entity: str
    evidence: str
    severity: str


class DiagramVerdict(BaseModel):
    clean: bool
    findings: list[DiagramFinding] = Field(default_factory=list)

    def bind_family(self, expected_family: str) -> DiagramVerdict:
        """Force findings into the page's own ID family.

        A judge told to audit an ERD that answers with family='UC' is
        misbehaving; the ledger ID must still be stable, so the server
        rewrites family to the page's family rather than letting model
        whims change ID namespaces."""
        fixed = [
            f if f.family == expected_family else f.model_copy(update={"family": expected_family})
            for f in self.findings
        ]
        return DiagramVerdict(clean=self.clean, findings=fixed)


class DiagramRequest(Strict):
    page_index: int = Field(ge=0, le=2000)
    diagram_type: DiagramType
    context_text: str = ""
    image_b64: str = Field(min_length=16, max_length=4_000_000)

    @field_validator("context_text")
    @classmethod
    def _cap_context(cls, v: str) -> str:
        # The context block is truncated, not rejected: a detector page's
        # surrounding text can be long, and the prompt only needs a hint.
        return v[:4000]


class DiagramResponse(Strict):
    page_index: int
    diagram_type: DiagramType
    describe: DiagramDescribe
    verdict: DiagramVerdict
    model: str
    cached: bool
    mock: bool


def diagram_cache_key(
    *,
    payload: DiagramRequest,
    provider_name: str,
    mock_mode: str,
    model_selection: str,
    prompt_version: str,
) -> str:
    # c3fc786 rule: every value that reaches the prompt is in here —
    # image bytes, type, (already truncated) context, page index.
    return cache_key(
        "diagram",
        str(payload.page_index),
        payload.diagram_type.value,
        payload.context_text,
        payload.image_b64,
        provider_name,
        mock_mode,
        model_selection,
        prompt_version,
    )
