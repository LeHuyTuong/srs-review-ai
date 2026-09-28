"""WP7 — bộ dụng cụ gold set: lấy mẫu, ghi sheet, đo độ khớp, tính precision/recall.

Gold set là nơi **người khác** tự chấm. Người tự dán nhãn rồi tự chấm thì đó là
gold set vô giá trị (plan 10 §3, nguyên văn). Vì thế công cụ này **không tạo nhãn
vàng**: nó không đóng gói sẵn dữ liệu mẫu, không tự điền cột `finding`, và không
bao giờ in ra một con số precision/recall khi hai người chấm chưa khớp ≥ 80%.

Nó làm đúng bốn việc để khi hai người ngồi ký thì việc đo chạy được ngay:

  1. ``sample_units()``     rút mẫu **phân tầng** từ inventory các unit đã parse
  2. ``annotate_sheet()``   ghi sheet **trống** cho hai người điền độc lập
  3. ``agreement()``        tỉ lệ khớp giữa hai người, ngưỡng 80% (plan 10 §3)
  4. ``precision_recall()`` chỉ chạy khi (3) đã ĐẠT — dưới ngưỡng thì **từ chối**

Vì sao phải phân tầng: OTES có những bẫy đã đo được — ID trùng có hệ thống (UC04
dùng cho 7+ chức năng, UC021 cho cả "đóng nhóm" lẫn "đuổi học viên"), NFR viết
thành văn nên parser ra `section`, và thân UC bị tách thành `SEC-...` khi mất
flow. Lấy mẫu ngẫu nhiên thuần sẽ phủ gần hết là use case, còn đúng những chỗ
khó thì không ai chấm — mẫu "đẹp" mà vô dụng. Mọi số đếm được in kèm cách đếm,
vì "63 bảng / 52 ID xuất hiện / 24 ID duy nhất" là ba con số khác nhau cho cùng
một tài liệu (AGENTS.md).

Phân tầng (ưu tiên từ trên xuống, mỗi unit vào **đúng một** tầng — số unit khớp
nhiều tầng được in riêng để không giấu phần chồng lấn):

  ``section_is_uc_body``   unit kind `Section` mà thân là một use case (≥2 dấu hiệu
                           Actor/Goal/Preconditions/Postconditions/Main flow…)
                           — dấu hiệu dữ liệu đã hỏng ở tầng parser
  ``duplicate_uc_id``      use case có ID xuất hiện nhiều lần **trong cùng một lượt**
  ``uc_with_main_flow``    use case còn nguyên main flow
  ``business_rule``        unit kind `Business rule`
  ``nfr_as_prose``         NFR viết thành văn: kind `Non-functional`, hoặc unit
                           kind `Section` mang dấu hiệu chất lượng đo được
  ``other``                phần còn lại (gồm cả use case **mất** main flow)

Sheet annotation là CSV với cột ``source_round, unit_id, unit_kind, stratum, text,
annotator, finding, criterion_id, note``. Cột ``annotator`` là **bắt buộc**: thiếu
nó thì không tính được độ khớp giữa hai người, và không có gì báo lỗi.
``source_round`` và ``stratum`` là hai cột thêm so với bảng cột tối thiểu của
plan, vì thiếu chúng thì sheet không nói được unit đến từ lượt nào (OTES trùng ID
là chuyện thường) và người chấm không biết mình đang chấm tầng nào.

Chạy (thuần stdlib — không cần API key, không tốn quota, không chạm cache server):

    python docs/evidence/scripts/goldset_instrument.py --help

    # 1. rút mẫu từ inventory đã lưu (file có mảng `units` — payload phiên trong
    #    Lịch sử, hoặc chính file đó với nhiều lượt trong khoá `rounds`)
    python docs/evidence/scripts/goldset_instrument.py sample \\
        --units goldset-raw-units.json --out goldset-sheet-A.csv --n 24

    # 2. hai người điền sheet-A.csv / sheet-B.csv ĐỘC LẬP, rồi đo khớp
    python docs/evidence/scripts/goldset_instrument.py agreement \\
        --a goldset-sheet-A.csv --b goldset-sheet-B.csv

    # 3. chỉ chạy được khi bước 2 đạt ≥ 80%
    python docs/evidence/scripts/goldset_instrument.py score \\
        --a goldset-sheet-A.csv --b goldset-sheet-B.csv --system goldset-sheet-system.csv

Mã thoát: 0 = tin cậy được / đã tính; 1 = **chưa đủ tin cậy, đã từ chối**;
2 = sai đầu vào hoặc thiếu tham số.
"""

from __future__ import annotations

import argparse
import contextlib
import csv
import json
import random
import re
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SEED = 20260927
DEFAULT_SAMPLE_SIZE = 24
"""plan 10 §3: "Chọn 1 tài liệu, 1 loại finding, 20–30 mẫu" — 24 nằm giữa khoảng."""

AGREEMENT_THRESHOLD = 0.80
"""plan 10 §3 bước 4: chỉ khi hai người khớp trên ≥ 80% mẫu thì mốc đó mới là gold."""

MIN_LABELLED_SAMPLES = 20
"""Sàn theo plan 10 §3. Độ khớp 100% trên 3 dòng là đồng thuận giả: hai người cùng
bỏ trống phần khó rồi cùng đạt — con số đó không chứng minh gì."""

FINDING_PRESENT = "present"
FINDING_ABSENT = "absent"
FINDINGS = (FINDING_PRESENT, FINDING_ABSENT)

SHEET_COLUMNS = (
    "source_round",
    "unit_id",
    "unit_kind",
    "stratum",
    "text",
    "annotator",
    "finding",
    "criterion_id",
    "note",
)
"""Cột `text` bị cắt còn `TEXT_LIMIT` ký tự khi ghi CSV — xem `TEXT_LIMIT`."""

LABEL_COLUMNS = ("annotator", "finding", "criterion_id", "note")
"""Bốn cột người chấm điền. Sheet do `annotate_sheet()` sinh ra để **trống** cả bốn."""

ROW_KEY_COLUMNS = ("source_round", "unit_id", "criterion_id")
"""Khoá nhận dạng một dòng giữa hai sheet. `criterion_id` nằm trong khoá vì một
unit có thể bị chấm theo nhiều tiêu chí (chain 1/2/3)."""

TEXT_LIMIT = 2000
"""Một thân UC dài có thể vài nghìn ký tự; sheet phải mở được bằng Excel và người
chấm phải thấy đủ ngữ cảnh để quyết định present/absent."""

STRATUM_UC_BODY_SECTION = "section_is_uc_body"
STRATUM_DUPLICATE_UC_ID = "duplicate_uc_id"
STRATUM_UC_MAIN_FLOW = "uc_with_main_flow"
STRATUM_BUSINESS_RULE = "business_rule"
STRATUM_NFR_PROSE = "nfr_as_prose"
STRATUM_OTHER = "other"

STRATA = (
    STRATUM_UC_BODY_SECTION,
    STRATUM_DUPLICATE_UC_ID,
    STRATUM_UC_MAIN_FLOW,
    STRATUM_BUSINESS_RULE,
    STRATUM_NFR_PROSE,
    STRATUM_OTHER,
)
"""Thứ tự này vừa là thứ tự ưu tiên khi gán tầng, vừa là thứ tự trong báo cáo."""

STRATUM_VN = {
    STRATUM_UC_BODY_SECTION: "section thực ra là thân UC",
    STRATUM_DUPLICATE_UC_ID: "use case trùng ID",
    STRATUM_UC_MAIN_FLOW: "use case còn main flow",
    STRATUM_BUSINESS_RULE: "business rule",
    STRATUM_NFR_PROSE: "NFR viết thành văn",
    STRATUM_OTHER: "còn lại",
}

KIND_USE_CASE = "use case"
KIND_BUSINESS_RULE = "business rule"
KIND_NON_FUNCTIONAL = "non-functional"
KIND_SECTION = "section"

_MAIN_FLOW = re.compile(
    r"main\s+(success\s+)?(scenario|flow)|luồng chính|kịch bản chính",
    re.IGNORECASE,
)
_UC_BODY_MARKER = re.compile(
    r"\b(actor|goal|preconditions?|postconditions?|main\s+(success\s+)?(scenario|flow)|"
    r"alternative\s+flow|exceptions?|extensions?)\b",
    re.IGNORECASE,
)
_NFR_PROSE = re.compile(
    r"(thời gian phản hồi|response\s+time|throughput|availability|khả dụng|bảo mật|"
    r"security|hiệu năng|performance|độ trễ|latency|uptime|concurrent\s+users|"
    r"người dùng đồng thời|sẵn sàng)",
    re.IGNORECASE,
)
_UC_BODY_MIN_MARKERS = 2


class GoldSetError(Exception):
    """Đầu vào không dùng được (thiếu cột, nhãn trùng, hai sheet cùng một người…)."""


class GoldSetNotReliableError(GoldSetError):
    """Hai người chưa khớp ≥ 80%: gold set chưa đủ tin cậy để đo precision/recall."""


def _force_utf8_stdout() -> None:
    """Console Windows ở đây là cp1258: print tiếng Việt sẽ ném UnicodeEncodeError
    giữa lúc chạy (mất phần đã in, phần ghi file chưa chạy). Gọi trước mọi print."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        # stream đã bị thay/đóng (pytest capture) thì bỏ qua, không phải lỗi.
        with contextlib.suppress(ValueError, OSError):
            reconfigure(encoding="utf-8", errors="replace")


def _emit(line: str = "") -> None:
    """In một dòng, và nếu console vẫn không nhận được tiếng Việt thì in bản thay
    thế thay vì ném giữa chừng. Chịu lỗi phải chủ ý, không phải im lặng."""
    try:
        print(line, flush=True)
    except UnicodeEncodeError:
        print(line.encode("ascii", "replace").decode("ascii"), flush=True)


_force_utf8_stdout()


# --------------------------------------------------------------------------- #
# Dữ liệu vào: unit của inventory đã parse
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Unit:
    """Một dòng inventory, đúng hình dạng ``WorkspaceUnit.toJson()`` của app."""

    round_label: str
    unit_id: str
    kind: str
    text: str
    key: str

    @property
    def kind_norm(self) -> str:
        return (self.kind or "").strip().lower()

    @property
    def is_use_case(self) -> bool:
        if self.kind_norm == KIND_USE_CASE:
            return True
        return self.unit_id.upper().startswith("UC") and self.kind_norm != KIND_SECTION


@dataclass(frozen=True)
class Round:
    """Một lượt chấm (một tài liệu đã parse). Trùng ID **giữa các lượt** là bình
    thường — bản sửa lặp lại ID; trùng **trong một lượt** mới là bẫy."""

    label: str
    units: tuple[Unit, ...]


def _unit_from_json(raw: object, *, round_label: str, index: int) -> Unit:
    if not isinstance(raw, dict):
        raise GoldSetError(f"{round_label}: unit #{index} không phải object JSON (nhận {type(raw).__name__})")
    unit_id = str(raw.get("id") or "").strip()
    if not unit_id:
        raise GoldSetError(
            f"{round_label}: unit #{index} không có `id` — không lấy mẫu được trên dòng không có định danh"
        )
    return Unit(
        round_label=round_label,
        unit_id=unit_id,
        kind=str(raw.get("kind") or ""),
        text=str(raw.get("text") or ""),
        key=str(raw.get("key") or f"{index}-{unit_id}"),
    )


def _rounds_from_object(payload: object, *, label: str) -> list[Round]:
    """Nhận cả payload phiên (`units`), cả danh sách lượt (`rounds`), cả mảng unit."""

    def one(units: object, round_label: str) -> Round:
        if not isinstance(units, list):
            raise GoldSetError(f"{round_label}: `units` phải là mảng JSON")
        parsed = tuple(
            _unit_from_json(item, round_label=round_label, index=i) for i, item in enumerate(units)
        )
        seen: dict[str, int] = {}
        for unit in parsed:
            seen[unit.key] = seen.get(unit.key, 0) + 1
        collision = sorted(k for k, v in seen.items() if v > 1)
        if collision:
            raise GoldSetError(
                f"{round_label}: khoá unit bị lặp {collision[:3]} — inventory hỏng, "
                "sửa nguồn trước khi lấy mẫu"
            )
        return Round(label=round_label, units=parsed)

    if isinstance(payload, list):
        return [one(payload, label)]
    if isinstance(payload, dict):
        if "rounds" in payload:
            entries = payload["rounds"]
            if not isinstance(entries, list):
                raise GoldSetError(f"{label}: `rounds` phải là mảng")
            out = []
            for i, entry in enumerate(entries):
                if not isinstance(entry, dict) or "units" not in entry:
                    raise GoldSetError(f"{label}: rounds[{i}] phải có khoá `units`")
                name = str(entry.get("label") or entry.get("round") or f"{label}#{i + 1}")
                out.append(one(entry["units"], name))
            return out
        if "units" in payload:
            return [one(payload["units"], label)]
    raise GoldSetError(f"{label}: không thấy `units` (payload phiên) hay `rounds` (nhiều lượt)")


def load_rounds(paths: Iterable[str | Path]) -> list[Round]:
    """Đọc một hay nhiều file JSON thành danh sách lượt. Nhãn lượt = tên file."""

    rounds: list[Round] = []
    for raw_path in paths:
        path = Path(raw_path)
        if not path.exists():
            raise GoldSetError(f"không tìm thấy {path}")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise GoldSetError(f"{path}: JSON hỏng — {exc}") from exc
        rounds.extend(_rounds_from_object(payload, label=path.stem))
    if not rounds:
        raise GoldSetError("không có lượt nào để lấy mẫu")
    return rounds


# --------------------------------------------------------------------------- #
# Phân tầng
# --------------------------------------------------------------------------- #


def _matches(unit: Unit, duplicate_ids: set[str]) -> set[str]:
    """Mọi tầng mà unit này khớp — trả về TẤT CẢ, không chỉ tầng được chọn."""

    text = unit.text
    hits: set[str] = set()
    markers = len(set(m.group(0).lower() for m in _UC_BODY_MARKER.finditer(text)))
    if unit.kind_norm == KIND_SECTION and markers >= _UC_BODY_MIN_MARKERS:
        hits.add(STRATUM_UC_BODY_SECTION)
    if unit.is_use_case and unit.unit_id.upper() in duplicate_ids:
        hits.add(STRATUM_DUPLICATE_UC_ID)
    if unit.is_use_case and _MAIN_FLOW.search(text):
        hits.add(STRATUM_UC_MAIN_FLOW)
    if unit.kind_norm == KIND_BUSINESS_RULE:
        hits.add(STRATUM_BUSINESS_RULE)
    if unit.kind_norm == KIND_NON_FUNCTIONAL or (unit.kind_norm == KIND_SECTION and _NFR_PROSE.search(text)):
        hits.add(STRATUM_NFR_PROSE)
    if not hits:
        hits.add(STRATUM_OTHER)
    return hits


def strata_of(rounds: Sequence[Round]) -> dict[str, str]:
    """Tầng của từng unit, khoá ``(round_label, key)``. Tầng = tầng đầu tiên khớp
    theo thứ tự `STRATA` (unit khớp nhiều tầng vào tầng đặc thù nhất)."""

    out: dict[str, str] = {}
    for round_ in rounds:
        duplicates = _duplicate_ids(round_)
        for unit in round_.units:
            hits = _matches(unit, duplicates)
            chosen = next(s for s in STRATA if s in hits)
            out[f"{unit.round_label}\u0000{unit.key}"] = chosen
    return out


def _duplicate_ids(round_: Round) -> set[str]:
    """ID xuất hiện > 1 lần **trong cùng lượt** — cách đếm được in ra kèm số sử dụng."""

    counts: dict[str, int] = {}
    for unit in round_.units:
        counts[unit.unit_id.upper()] = counts.get(unit.unit_id.upper(), 0) + 1
    return {i for i, n in counts.items() if n > 1}


@dataclass(frozen=True)
class SampledUnit:
    unit: Unit
    stratum: str

    @property
    def sheet_row(self) -> dict[str, str]:
        row = {
            "source_round": self.unit.round_label,
            "unit_id": self.unit.unit_id,
            "unit_kind": self.unit.kind,
            "stratum": self.stratum,
            "text": self.unit.text[:TEXT_LIMIT],
        }
        for column in LABEL_COLUMNS:
            row[column] = ""
        return row


@dataclass(frozen=True)
class Sample:
    """Kết quả lấy mẫu kèm **cách đếm** — mọi phát biểu về số lượng phải nói rõ
    đếm theo cách nào (AGENTS.md: 63 bảng / 52 ID / 24 ID là ba con số khác nhau)."""

    rows: tuple[SampledUnit, ...]
    counts: dict[str, int]
    overlaps: int
    duplicate_ids: tuple[str, ...]
    units_total: int
    distinct_ids: int
    ids_appearing_more_than_once: int
    rounds: tuple[str, ...]
    n_requested: int
    seed: int

    def describe(self) -> str:
        lines = [
            f"Lấy mẫu {len(self.rows)}/{self.units_total} unit (xin {self.n_requested}, seed {self.seed})",
            f"  lượt: {', '.join(self.rounds)}",
            "  đếm theo tầng (mỗi unit chỉ vào một tầng, ưu tiên từ trên xuống):",
        ]
        for stratum in STRATA:
            lines.append(f"    {stratum:<22} {self.counts.get(stratum, 0):>4}  ({STRATUM_VN[stratum]})")
        lines.append(
            f"  unit khớp nhiều tầng: {self.overlaps} "
            "(đã gán vào tầng đặc thù nhất, con số này không bị giấu)"
        )
        lines.append(
            f"  ID: {self.distinct_ids} ID khác nhau, "
            f"{self.ids_appearing_more_than_once} ID xuất hiện >1 lần trong một lượt "
            f"→ {', '.join(self.duplicate_ids) if self.duplicate_ids else 'không có'}"
        )
        return "\n".join(lines)


def _allocate(sizes: dict[str, int], n: int) -> dict[str, int]:
    """Chia n suất theo tỉ lệ kích thước tầng (largest remainder), mỗi tầng khác
    rỗng ít nhất 1 suất. Tất định: cùng sizes + n thì cùng kết quả."""

    total = sum(sizes.values())
    if n <= 0 or total == 0:
        return {k: 0 for k in sizes}
    if n >= total:
        return dict(sizes)

    quotas = {k: (v * n / total) for k, v in sizes.items()}
    seats = {k: int(q) for k, q in quotas.items()}
    left = n - sum(seats.values())
    order = sorted(sizes, key=lambda k: (-(quotas[k] - seats[k]), k))
    while left > 0:
        progressed = False
        for k in order:
            if left == 0:
                break
            if seats[k] < sizes[k]:
                seats[k] += 1
                left -= 1
                progressed = True
        if not progressed:  # mọi tầng đã chạm trần: chỉ xảy ra khi n >= total
            break

    for k, size in sizes.items():  # sàn: tầng khác rỗng phải có mặt
        if size > 0 and seats[k] == 0:
            donors = [x for x in sizes if seats[x] > 1]
            if not donors:
                continue
            donor = max(donors, key=lambda x: (seats[x], x))
            seats[donor] -= 1
            seats[k] += 1
    return seats


def sample_units(
    rounds: Sequence[Round],
    n: int = DEFAULT_SAMPLE_SIZE,
    seed: int = DEFAULT_SEED,
) -> Sample:
    """Rút mẫu phân tầng, tất định theo `seed` (cùng mẫu + cùng seed ⇒ cùng sheet).

    **Từ chối** khi `n` nhỏ hơn số tầng khác rỗng: một mẫu bỏ trống tầng không còn
    là mẫu phân tầng, và nó sẽ bỏ trống đúng những tầng khó — thứ mà phân tầng tồn
    tại để phủ.
    """

    if not rounds:
        raise GoldSetError("không có lượt nào để lấy mẫu")
    if n <= 0:
        raise GoldSetError(f"n={n}: cần ít nhất 1 unit để lấy mẫu")

    assignment = strata_of(rounds)
    pools: dict[str, list[Unit]] = {s: [] for s in STRATA}
    for round_ in rounds:
        for unit in round_.units:
            pools[assignment[f"{unit.round_label}\u0000{unit.key}"]].append(unit)

    sizes = {s: len(pools[s]) for s in STRATA}
    non_empty = [s for s in STRATA if sizes[s] > 0]
    if n < len(non_empty):
        raise GoldSetError(
            f"n={n} nhỏ hơn số tầng khác rỗng ({len(non_empty)}: {', '.join(non_empty)}) — "
            "tăng n, hoặc lọc bớt trước khi lấy mẫu; mẫu bỏ trống một tầng là mẫu "
            "lệch, không phải mẫu phân tầng"
        )
    seats = _allocate(sizes, n)
    starved = [s for s in non_empty if seats.get(s, 0) == 0]
    if starved:  # hàng rào: bỏ trống một tầng là lỗi, không phải một kết quả
        raise GoldSetError(f"lấy mẫu bỏ trống tầng {starved} — tăng n lên trên {len(non_empty)}")
    rng = random.Random(seed)  # noqa: S311 — mẫu tất định, không phải crypto

    rows: list[SampledUnit] = []
    for stratum in STRATA:
        pool = sorted(pools[stratum], key=lambda u: (u.round_label, u.unit_id, u.key))
        take = seats.get(stratum, 0)
        if take <= 0:
            continue
        drawn = pool if take >= len(pool) else rng.sample(pool, take)
        rows.extend(SampledUnit(unit=u, stratum=stratum) for u in drawn)
    rows.sort(key=lambda r: (r.unit.round_label, r.stratum, r.unit.unit_id, r.unit.key))

    all_units = [u for round_ in rounds for u in round_.units]
    dupes = sorted({i for round_ in rounds for i in _duplicate_ids(round_)})
    overlaps = 0
    for round_ in rounds:
        duplicates = _duplicate_ids(round_)
        for unit in round_.units:
            if len(_matches(unit, duplicates)) > 1:
                overlaps += 1

    return Sample(
        rows=tuple(rows),
        counts={s: sum(1 for r in rows if r.stratum == s) for s in STRATA},
        overlaps=overlaps,
        duplicate_ids=tuple(dupes),
        units_total=len(all_units),
        distinct_ids=len({u.unit_id.upper() for u in all_units}),
        ids_appearing_more_than_once=len(dupes),
        rounds=tuple(r.label for r in rounds),
        n_requested=n,
        seed=seed,
    )


# --------------------------------------------------------------------------- #
# Sheet annotation
# --------------------------------------------------------------------------- #


def write_sheet(rows: Sequence[dict[str, str]], path: str | Path) -> Path:
    """Ghi sheet với đúng `SHEET_COLUMNS`; cột thiếu được điền rỗng."""

    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(SHEET_COLUMNS), extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in SHEET_COLUMNS})
    return out


def annotate_sheet(sample: Sample, path: str | Path) -> Path:
    """Ghi sheet **TRỐNG** cho người chấm. Không điền `finding`: tự dán nhãn rồi tự
    chấm là chữ ký của một gold set vô giá trị (plan 10 §3)."""

    return write_sheet([row.sheet_row for row in sample.rows], path)


@dataclass(frozen=True)
class Sheet:
    path: str
    annotator: str
    rows: tuple[dict[str, str], ...]

    def labels(self) -> dict[tuple[str, str, str], str]:
        """Khoá dòng → nhãn đã chuẩn hoá. Nhãn rỗng = "chưa dán", không phải âm."""

        out: dict[tuple[str, str, str], str] = {}
        for row in self.rows:
            key = tuple((row.get(column) or "").strip() for column in ROW_KEY_COLUMNS)
            if key in out:
                raise GoldSetError(
                    f"{self.path}: khoá {key} bị lặp — nhãn vàng phải rõ nghĩa, "
                    "một dòng một unit một tiêu chí"
                )
            out[key] = (row.get("finding") or "").strip().lower()
        return out


def read_sheet(path: str | Path) -> Sheet:
    """Đọc sheet và kiểm tra cấu trúc. Thiếu `annotator` là lỗi, không phải cảnh báo:
    không có nó thì độ khớp giữa hai người không tính được và không gì báo lỗi."""

    source = Path(path)
    if not source.exists():
        raise GoldSetError(f"không tìm thấy sheet {source}")
    with source.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        header = tuple(reader.fieldnames or ())
        missing = [c for c in SHEET_COLUMNS if c not in header]
        if missing:
            raise GoldSetError(
                f"{source}: thiếu cột {missing} — sheet phải giữ đúng cột của annotate_sheet()"
            )
        rows = tuple({k: (v or "") for k, v in row.items() if k} for row in reader)

    names = sorted({(row.get("annotator") or "").strip() for row in rows} - {""})
    if not names:
        raise GoldSetError(
            f"{source}: không có tên người chấm ở cột `annotator` — sheet trắng "
            "không dùng được để tính độ khớp"
        )
    if len(names) > 1:
        raise GoldSetError(
            f"{source}: có {len(names)} người chấm trong một sheet ({names}) — "
            "mỗi người một file, dán độc lập"
        )

    seen: set[tuple[str, str, str]] = set()
    for index, row in enumerate(rows, start=2):
        value = (row.get("finding") or "").strip().lower()
        if value and value not in FINDINGS:
            raise GoldSetError(f"{source}: dòng {index} `finding`={value!r} — chỉ nhận {FINDINGS}")
        key = tuple((row.get(column) or "").strip() for column in ROW_KEY_COLUMNS)
        if key in seen:
            raise GoldSetError(
                f"{source}: dòng {index} trùng khoá {key} — một unit một tiêu chí "
                "chỉ được có một dòng, nếu không thì không biết dòng nào là nhãn vàng"
            )
        seen.add(key)
    return Sheet(path=str(source), annotator=names[0], rows=rows)


# --------------------------------------------------------------------------- #
# Độ khớp giữa hai người
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Agreement:
    annotator_a: str
    annotator_b: str
    n_labelled: int
    agreed: int
    disagreed: int
    unlabelled: int
    ratio: float | None
    threshold: float
    reliable: bool
    reason: str

    def describe(self) -> str:
        share = "n/a" if self.ratio is None else f"{self.ratio:.1%}"
        verdict = "ĐỦ TIN CẬY" if self.reliable else "CHƯA ĐỦ TIN CẬY"
        lines = [
            f"Độ khớp {self.annotator_a} × {self.annotator_b}: {share} "
            f"({self.agreed}/{self.n_labelled} dòng, ngưỡng {self.threshold:.0%}) — {verdict}",
            f"  lệch: {self.disagreed}  ·  dòng một người dán người kia để trống: {self.unlabelled}",
        ]
        if self.reason:
            lines.append(f"  lý do: {self.reason}")
        if not self.reliable:
            lines.append("  → TỪ CHỐI đo precision/recall trên gold set này.")
        return "\n".join(lines)


def agreement(
    sheet_a: str | Path,
    sheet_b: str | Path,
    *,
    threshold: float = AGREEMENT_THRESHOLD,
    min_labelled: int = MIN_LABELLED_SAMPLES,
) -> Agreement:
    """Tỉ lệ dòng hai người khớp trên `(finding, criterion_id)`.

    Một dòng tính là **khớp** khi cả hai người cùng dán nhãn và nhãn giống nhau.
    Dòng chỉ một người dán (kể cả khi người kia để trống trong template) là **lệch**
    nếu người kia có dán ở dòng đó; nếu cả hai đều để trống thì đó là dòng chưa
    dán, bị loại khỏi mẫu số và đếm riêng ở `unlabelled`.
    """

    a, b = read_sheet(sheet_a), read_sheet(sheet_b)
    if a.annotator == b.annotator:
        raise GoldSetError(
            f"hai sheet cùng một người chấm ({a.annotator!r}) — đồng thuận với chính "
            "mình không phải là đồng thuận"
        )

    la, lb = a.labels(), b.labels()
    keys = set(la) | set(lb)
    labelled = [k for k in sorted(keys) if la.get(k) and lb.get(k)]
    unlabelled = len(keys) - len(labelled)
    agreed = sum(1 for k in labelled if la[k] == lb[k])
    disagreed = len(labelled) - agreed

    n = len(labelled)
    if n == 0:
        return Agreement(
            annotator_a=a.annotator,
            annotator_b=b.annotator,
            n_labelled=0,
            agreed=0,
            disagreed=0,
            unlabelled=unlabelled,
            ratio=None,
            threshold=threshold,
            reliable=False,
            reason="không có dòng nào được cả hai người dán nhãn",
        )

    ratio = agreed / n
    if n < min_labelled:
        return Agreement(
            annotator_a=a.annotator,
            annotator_b=b.annotator,
            n_labelled=n,
            agreed=agreed,
            disagreed=disagreed,
            unlabelled=unlabelled,
            ratio=ratio,
            threshold=threshold,
            reliable=False,
            reason=(
                f"chỉ {n} dòng được dán nhãn, dưới sàn {min_labelled} "
                "(plan 10 §3: 20–30 mẫu) — 100% trên vài dòng là đồng thuận giả"
            ),
        )

    reliable = ratio >= threshold
    reason = "" if reliable else f"độ khớp {ratio:.1%} dưới ngưỡng {threshold:.0%}"
    return Agreement(
        annotator_a=a.annotator,
        annotator_b=b.annotator,
        n_labelled=n,
        agreed=agreed,
        disagreed=disagreed,
        unlabelled=unlabelled,
        ratio=ratio,
        threshold=threshold,
        reliable=reliable,
        reason=reason,
    )


# --------------------------------------------------------------------------- #
# Precision / recall — chỉ khi agreement đã ĐẠT
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Scores:
    tp: int
    fp: int
    fn: int
    tn: int
    precision: float | None
    recall: float | None
    precision_reason: str
    recall_reason: str

    def describe(self) -> str:
        def show(value: float | None, reason: str) -> str:
            return "không xác định" if value is None else f"{value:.1%}" + (f" ({reason})" if reason else "")

        return (
            f"TP={self.tp} FP={self.fp} FN={self.fn} TN={self.tn}  ·  "
            f"precision={show(self.precision, self.precision_reason)}  ·  "
            f"recall={show(self.recall, self.recall_reason)}"
        )


def precision_recall(
    sheet_human: str | Path,
    sheet_system: str | Path,
    agreement_result: Agreement | None = None,
) -> Scores:
    """Precision/recall của hệ thống so với nhãn vàng. **Bắt buộc** truyền kết quả
    `agreement()` đã ĐẠT: gọi thiếu tham số này là từ chối, không phải mặc định tính.
    Đo precision/recall trên một gold set chưa đủ tin cậy là đo cái không chắc."""

    if agreement_result is None:
        raise GoldSetNotReliableError(
            "chưa có kết quả độ khớp giữa hai người: chạy agreement() trước rồi "
            "truyền kết quả vào (`agreement_result=`)"
        )
    if not agreement_result.reliable:
        raise GoldSetNotReliableError(
            f"hai người chưa khớp ≥ {agreement_result.threshold:.0%}: {agreement_result.reason}"
        )

    human, system = read_sheet(sheet_human), read_sheet(sheet_system)
    lh, ls = human.labels(), system.labels()
    keys = sorted(set(lh) | set(ls))

    tp = fp = fn = tn = 0
    unlabelled: list[tuple[str, str, str]] = []
    for key in keys:
        want, got = lh.get(key, ""), ls.get(key, "")
        if not want or not got:
            if want or got:  # một bên dán, bên kia thiếu: đếm riêng, không đoán
                unlabelled.append(key)
            continue
        if want == FINDING_PRESENT and got == FINDING_PRESENT:
            tp += 1
        elif want == FINDING_ABSENT and got == FINDING_PRESENT:
            fp += 1
        elif want == FINDING_PRESENT and got == FINDING_ABSENT:
            fn += 1
        else:
            tn += 1
    if unlabelled:
        raise GoldSetError(
            f"{len(unlabelled)} dòng chỉ một bên dán nhãn (ví dụ {unlabelled[:2]}) — "
            "hai sheet phải phủ cùng tập dòng trước khi tính điểm"
        )

    precision = tp / (tp + fp) if (tp + fp) else None
    recall = tp / (tp + fn) if (tp + fn) else None
    return Scores(
        tp=tp,
        fp=fp,
        fn=fn,
        tn=tn,
        precision=precision,
        recall=recall,
        precision_reason="" if precision is not None else "hệ thống không báo động nào",
        recall_reason="" if recall is not None else "nhãn vàng không có dòng present nào",
    )


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def _cmd_sample(args: argparse.Namespace) -> int:
    rounds = load_rounds(args.units)
    sample = sample_units(rounds, n=args.n, seed=args.seed)
    _emit(sample.describe())
    out = Path(args.out)
    if out.exists() and not args.force:
        _emit(f"\n{out} đã tồn tại — sheet đã ký có thể bị ghi đè. Dùng --force nếu chắc.")
        return 2
    annotate_sheet(sample, out)
    _emit(f"\nđã ghi sheet TRỐNG: {out}")
    _emit("  hai người điền cột `annotator` (tên khác nhau) và `finding` ∈ {present, absent}")
    _emit("  độc lập, không xem output của AI, rồi chạy: agreement --a … --b …")
    return 0


def _cmd_agreement(args: argparse.Namespace) -> int:
    result = agreement(args.a, args.b, min_labelled=args.min_labelled)
    _emit(result.describe())
    return 0 if result.reliable else 1


def _cmd_score(args: argparse.Namespace) -> int:
    result = agreement(args.a, args.b, min_labelled=args.min_labelled)
    _emit(result.describe())
    if not result.reliable:
        return 1
    scores = precision_recall(args.a, args.system, agreement_result=result)
    _emit(scores.describe())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Bộ dụng cụ gold set: lấy mẫu phân tầng, ghi sheet trống, đo độ khớp "
            "hai người (≥ 80%), chỉ khi đạt mới tính precision/recall. "
            "Công cụ KHÔNG tạo nhãn vàng."
        )
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_sample = sub.add_parser("sample", help="rút mẫu phân tầng và ghi sheet trống")
    p_sample.add_argument(
        "--units",
        action="append",
        required=True,
        help="file JSON có mảng `units` (payload phiên) hoặc `rounds`; lặp lại cho nhiều lượt",
    )
    p_sample.add_argument("--out", required=True, help="đường dẫn sheet CSV để ghi")
    p_sample.add_argument("--n", type=int, default=DEFAULT_SAMPLE_SIZE)
    p_sample.add_argument("--seed", type=int, default=DEFAULT_SEED)
    p_sample.add_argument("--force", action="store_true", help="cho phép ghi đè sheet có sẵn")
    p_sample.set_defaults(func=_cmd_sample)

    p_agr = sub.add_parser("agreement", help="tỉ lệ khớp giữa hai người chấm")
    p_agr.add_argument("--a", required=True)
    p_agr.add_argument("--b", required=True)
    p_agr.add_argument(
        "--min-labelled",
        type=int,
        default=MIN_LABELLED_SAMPLES,
        help=(
            f"sàn số dòng phải được cả hai dán nhãn, mặc định {MIN_LABELLED_SAMPLES} "
            "(plan 10 §3: 20–30 mẫu). Hạ sàn là hạ độ tin cậy: nếu hạ thì phải ghi "
            "con số đó vào tài liệu kết quả, đừng để nó biến mất"
        ),
    )
    p_agr.set_defaults(func=_cmd_agreement)

    p_score = sub.add_parser("score", help="precision/recall (chỉ khi độ khớp đã đạt)")
    p_score.add_argument("--a", required=True, help="sheet người chấm A (nhãn vàng)")
    p_score.add_argument("--b", required=True, help="sheet người chấm B (để đo độ khớp)")
    p_score.add_argument("--system", required=True, help="sheet của hệ thống")
    p_score.add_argument(
        "--min-labelled",
        type=int,
        default=MIN_LABELLED_SAMPLES,
        help=f"sàn số dòng phải được cả hai dán nhãn, mặc định {MIN_LABELLED_SAMPLES}",
    )
    p_score.set_defaults(func=_cmd_score)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    _force_utf8_stdout()
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except GoldSetNotReliableError as exc:
        _emit(f"TỪ CHỐI: {exc}")
        return 1
    except GoldSetError as exc:
        _emit(f"LỖI ĐẦU VÀO: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
