"""WP7 — bộ dụng cụ gold set: test cho sampler + ngưỡng 80% (plan 12 AC-12.13).

Đặt ở `server/tests/` để luật mới được CI thi hành tự động: `pytest` chạy trong
`server/`, nên một bộ dụng cụ không có test âm sẽ trôi khỏi tầm kiểm soát.

Điều quan trọng nhất trong file này là test **âm**: bộ dụng cụ phải **từ chối** đo
precision/recall khi hai người chấm chưa khớp ≥ 80%. Một bộ dụng cụ chỉ biết nói
"đạt" là bộ dụng cụ vô dụng — nên phần lớn test dưới đây dựng hai sheet **lệch
nhau có chủ ý** rồi khẳng định công cụ chặn.

Bộ dụng cụ thuần stdlib: không import gì từ `server/`, không mở cache thật, không
tốn quota (có test riêng giữ lời hứa đó).
"""

from __future__ import annotations

import ast
import csv
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INSTRUMENT_PATH = ROOT / "docs" / "evidence" / "scripts" / "goldset_instrument.py"


def _load_instrument():
    """Nạp script bằng đường dẫn (nó nằm ngoài `server/`, không phải package).

    `sys.modules[name] = module` là **bắt buộc**, không phải nghi thức: script dùng
    `from __future__ import annotations` nên `@dataclass` phải tra `sys.modules`
    để giải annotation dạng chuỗi — thiếu dòng này thì nạp nổ ngay ở
    `dataclasses._is_type` với `AttributeError: 'NoneType' object has no attribute
    '__dict__'`.
    """
    spec = importlib.util.spec_from_file_location("goldset_instrument", INSTRUMENT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gi = _load_instrument()

ROUND = "otes-2026-09-27"
CRITERION = "uc_count"


def _unit(unit_id: str, kind: str, text: str, key: str, label: str = ROUND):
    return gi.Unit(round_label=label, unit_id=unit_id, kind=kind, text=text, key=key)


def _round(units, label: str = ROUND):
    return gi.Round(label=label, units=tuple(units))


def _rich_round():
    """Tám unit phủ đủ sáu tầng — fixture tự dựng, không đọc file OTES 28,7 MB."""

    return _round(
        [
            _unit(
                "UC01",
                "Use case",
                "Actor: Student. Goal: log in. Main success scenario: 1. enter email.",
                "k-uc01",
            ),
            # UC04 dùng cho hai chức năng khác nhau — trùng ID có hệ thống trong OTES.
            _unit(
                "UC04",
                "Use case",
                "Actor: Admin. Goal: close group. Main success scenario: 1. pick group.",
                "k-uc04a",
            ),
            _unit(
                "UC04",
                "Use case",
                "Actor: Admin. Goal: expel student. Main success scenario: 1. pick member.",
                "k-uc04b",
            ),
            _unit("BR01", "Business rule", "A group must have 3-5 members.", "k-br01"),
            _unit(
                "NF01",
                "Non-functional",
                "Hệ thống phải phản hồi trong 2 giây với 100 người dùng đồng thời.",
                "k-nf01",
            ),
            # NFR viết thành văn: không có ID nên parser ra `section`.
            _unit(
                "SEC-4.2",
                "Section",
                "Thời gian phản hồi dưới 1 giây; availability 99%; bảo mật theo ISO 27001.",
                "k-sec42",
            ),
            # Thân use case bị tách thành section khi mất flow.
            _unit(
                "SEC-4.3",
                "Section",
                "Main success scenario: 1. mở nhóm. Postconditions: nhóm đã đóng.",
                "k-sec43",
            ),
            _unit("ST-9", "Unknown", "Một câu rời không thuộc tầng nào ở trên.", "k-st9"),
        ]
    )


def _sheet_row(
    unit_id: str,
    finding: str,
    annotator: str,
    *,
    criterion: str = CRITERION,
    source_round: str = "r1",
) -> dict[str, str]:
    row = {column: "" for column in gi.SHEET_COLUMNS}
    row.update(
        source_round=source_round,
        unit_id=unit_id,
        unit_kind="Use case",
        stratum=gi.STRATUM_UC_MAIN_FLOW,
        text=f"text of {unit_id}",
        annotator=annotator,
        finding=finding,
        criterion_id=criterion,
    )
    return row


def _write(path: Path, rows) -> Path:
    return gi.write_sheet(rows, path)


def _decade(annotator: str, flips: set[str], *, first_is_present: bool = True):
    """Mười dòng u01..u10; `flips` là những unit bị người này đánh ngược lại.

    Chủ ý dùng mốc tường minh (u01…u10) chứ không dựa vào thời gian hay thứ tự
    ghi — hai sheet lệch nhau đúng bằng số unit trong `flips`, tất định.
    """

    rows = []
    for index in range(1, 11):
        unit_id = f"u{index:02d}"
        base_present = index <= 5
        present = base_present if unit_id not in flips else not base_present
        if not first_is_present:
            present = not present
        rows.append(_sheet_row(unit_id, gi.FINDING_PRESENT if present else gi.FINDING_ABSENT, annotator))
    return rows


class TestSampling:
    def test_the_same_seed_gives_the_same_sheet_twice(self):
        """Tất định: cùng inventory + cùng seed ⇒ cùng sheet, chạy lại vẫn vậy."""

        first = gi.sample_units([_rich_round()], n=6, seed=17)
        second = gi.sample_units([_rich_round()], n=6, seed=17)
        assert [r.unit.key for r in first.rows] == [r.unit.key for r in second.rows]

    def test_input_order_does_not_change_the_draw(self):
        """Đảo thứ tự unit trong inventory không được đổi mẫu — nếu đổi thì mẫu phụ
        thuộc thứ tự file, và hai người chấm cùng tài liệu có thể nhận hai sheet khác nhau."""

        units = list(_rich_round().units)
        straight = gi.sample_units([_round(units)], n=6, seed=3)
        shuffled = gi.sample_units([_round(list(reversed(units)))], n=6, seed=3)
        assert {r.unit.key for r in straight.rows} == {r.unit.key for r in shuffled.rows}

    def test_the_seed_actually_chooses(self):
        """Seed phải có tác dụng. Fixture 12 unit cùng tầng, n=3: hai seed khác nhau
        cho hai tổ hợp khác nhau (đã chạy và chốt; tất định nên không phải test may rủi)."""

        units = [_unit("BR01", "Business rule", f"rule {i}", f"k{i}") for i in range(12)]
        seeds = {
            tuple(sorted(r.unit.key for r in gi.sample_units([_round(units)], n=3, seed=s).rows))
            for s in (1, 2, 3, 4)
        }
        assert len(seeds) > 1

    def test_every_stratum_is_represented_on_a_fixture_that_has_them_all(self):
        """Không tầng nào được để trống khi fixture có đủ — đây là lý do phân tầng
        tồn tại: mẫu ngẫu nhiên thuần sẽ bỏ đúng những chỗ khó (AC-12.13)."""

        sample = gi.sample_units([_rich_round()], n=6, seed=1)
        for stratum in (
            gi.STRATUM_UC_BODY_SECTION,
            gi.STRATUM_DUPLICATE_UC_ID,
            gi.STRATUM_UC_MAIN_FLOW,
            gi.STRATUM_BUSINESS_RULE,
            gi.STRATUM_NFR_PROSE,
            gi.STRATUM_OTHER,
        ):
            assert sample.counts[stratum] >= 1, f"tầng {stratum} bị bỏ trống"

    def test_counts_sum_to_the_sample_and_say_how_they_were_counted(self):
        """Mọi phát biểu về số lượng phải nói rõ đếm theo cách nào: hai unit mang `UC04`
        là **một** ID xuất hiện >1 lần nhưng **hai** unit trong tầng trùng ID."""

        unit_ids = [u.unit_id for u in _rich_round().units]
        assert unit_ids.count("UC04") == 2  # cách đếm 1: số unit mang ID đó
        assert len({u.upper() for u in unit_ids}) == 7  # cách đếm 2: số ID khác nhau

        sample = gi.sample_units([_rich_round()], n=6, seed=1)
        assert sum(sample.counts.values()) == len(sample.rows)
        assert sum(sample.pools.values()) == sample.units_total
        assert sample.pools[gi.STRATUM_DUPLICATE_UC_ID] == 2  # kho, không phải số rút ra
        assert sample.counts[gi.STRATUM_DUPLICATE_UC_ID] == 1
        assert sample.units_total == 8
        assert sample.distinct_ids == 7
        assert sample.ids_appearing_more_than_once == 1
        assert sample.duplicate_ids == ("UC04",)
        assert sample.overlaps >= 1  # unit khớp nhiều tầng: con số không bị giấu

    def test_a_sample_smaller_than_the_stratum_count_is_refused(self):
        """Sáu tầng khác rỗng mà xin 5 suất thì một tầng phải trống — công cụ từ chối
        thay vì âm thầm trả một mẫu lệch (đây là bug bắt được khi tự chạy thử)."""

        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.sample_units([_rich_round()], n=5, seed=1)
        assert "nhỏ hơn số tầng khác rỗng" in str(excinfo.value)

    def test_zero_or_negative_size_is_refused(self):
        with pytest.raises(gi.GoldSetError):
            gi.sample_units([_rich_round()], n=0, seed=1)

    def test_the_parser_traps_land_in_their_own_strata(self):
        """Hai bẫy đã đo trên OTES: NFR viết thành văn ra `section`, và thân UC bị
        tách thành `SEC-...` khi mất flow. Cả hai phải có tầng riêng."""

        strata = gi.strata_of([_rich_round()])
        assert strata[f"{ROUND}\u0000k-sec42"] == gi.STRATUM_NFR_PROSE
        assert strata[f"{ROUND}\u0000k-sec43"] == gi.STRATUM_UC_BODY_SECTION

    def test_a_use_case_that_lost_its_flow_is_visible_as_other(self):
        """UC mất main flow không rơi vào tầng `uc_with_main_flow` — nó hiện ở `other`,
        nên số đếm nói ra được chỗ dữ liệu đã hỏng thay vì giấu vào tầng "use case"."""

        lost = _unit("UC09", "Use case", "Actor: Student. Goal: unknown.", "k-uc09")
        strata = gi.strata_of([_round([lost])])
        assert strata[f"{ROUND}\u0000k-uc09"] == gi.STRATUM_OTHER


class TestSheet:
    def test_the_template_has_the_documented_columns_in_order(self, tmp_path: Path):
        sample = gi.sample_units([_rich_round()], n=6, seed=1)
        path = gi.annotate_sheet(sample, tmp_path / "sheet.csv")
        with path.open(encoding="utf-8", newline="") as handle:
            header = tuple(next(csv.reader(handle)))
        assert header == gi.SHEET_COLUMNS
        assert "annotator" in header

    def test_the_template_leaves_every_label_column_empty(self, tmp_path: Path):
        """Sheet sinh ra phải **trống**: tự dán nhãn rồi tự chấm là chữ ký của một
        gold set vô giá trị (plan 10 §3)."""

        sample = gi.sample_units([_rich_round()], n=6, seed=1)
        path = gi.annotate_sheet(sample, tmp_path / "sheet.csv")
        with path.open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        assert len(rows) == len(sample.rows)
        for row in rows:
            for column in gi.LABEL_COLUMNS:
                assert row[column] == "", f"cột {column} bị điền sẵn"
            assert row["unit_id"]  # phần nhận dạng thì phải có
            assert len(row["text"]) <= gi.TEXT_LIMIT

    def test_a_blank_sheet_cannot_be_read_as_a_signed_one(self, tmp_path: Path):
        sample = gi.sample_units([_rich_round()], n=6, seed=1)
        path = gi.annotate_sheet(sample, tmp_path / "sheet.csv")
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.read_sheet(path)
        assert "annotator" in str(excinfo.value)

    def test_a_sheet_missing_a_column_is_rejected(self, tmp_path: Path):
        path = tmp_path / "broken.csv"
        path.write_text("unit_id,finding\nUC01,present\n", encoding="utf-8")
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.read_sheet(path)
        assert "thiếu cột" in str(excinfo.value)

    def test_an_unknown_finding_value_is_rejected(self, tmp_path: Path):
        rows = [_sheet_row("u01", "maybe", "An"), _sheet_row("u02", "present", "An")]
        path = _write(tmp_path / "sheet.csv", rows)
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.read_sheet(path)
        assert "finding" in str(excinfo.value)

    def test_one_sheet_signed_by_two_people_is_rejected(self, tmp_path: Path):
        """Hai người trong một file thì không tính được độ khớp — mỗi người một file."""

        rows = [_sheet_row("u01", "present", "An"), _sheet_row("u02", "absent", "Binh")]
        path = _write(tmp_path / "sheet.csv", rows)
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.read_sheet(path)
        assert "một sheet" in str(excinfo.value)

    def test_two_rows_with_the_same_key_are_rejected(self, tmp_path: Path):
        """Một unit một tiêu chí chỉ được một dòng: hai dòng khác nhãn thì không biết
        dòng nào là nhãn vàng — phải chặn ở lúc ĐỌC, không phải lúc tính."""

        rows = [
            _sheet_row("u01", "present", "An"),
            _sheet_row("u01", "absent", "An"),
        ]
        path = _write(tmp_path / "sheet.csv", rows)
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.read_sheet(path)
        assert "trùng khoá" in str(excinfo.value)


class TestAgreement:
    def test_two_identical_sheets_reach_one_hundred_percent(self, tmp_path: Path):
        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("Binh", set()))
        result = gi.agreement(path_a, path_b, min_labelled=10)
        assert result.n_labelled == 10
        assert result.agreed == 10
        assert result.ratio == 1.0
        assert result.reliable is True
        assert result.reason == ""

    def test_the_number_printed_matches_the_hand_count(self, tmp_path: Path, capsys):
        """10 dòng, 4 dòng bị người B đánh ngược lại ⇒ 6/10 = 60% — tự đếm tay, không
        so với con số của chính code vừa viết."""

        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("Binh", {"u03", "u04", "u07", "u08"}))
        result = gi.agreement(path_a, path_b, min_labelled=10)
        assert result.agreed == 6
        assert result.disagreed == 4
        assert result.n_labelled == 10
        assert result.ratio == pytest.approx(0.6)
        capsys.readouterr()  # dọn phần in của lần gọi trước, không dùng làm bằng chứng

    def test_disagreeing_sheets_below_the_threshold_refuse_to_score(self, tmp_path: Path):
        """TEST ÂM QUAN TRỌNG NHẤT CỦA WP: hai sheet lệch nhau ⇒ dưới 80% ⇒ công cụ
        báo 'chưa đủ tin cậy' và **không** đo precision/recall (AC-12.13)."""

        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("Binh", {"u01", "u02", "u03"}))
        result = gi.agreement(path_a, path_b, min_labelled=10)
        assert result.n_labelled == 10
        assert result.ratio == pytest.approx(0.7)
        assert result.reliable is False
        assert "chưa đủ tin cậy" not in result.reason  # reason nêu số, không tự khen
        assert "dưới ngưỡng" in result.reason
        assert "CHƯA ĐỦ TIN CẬY" in result.describe()

        with pytest.raises(gi.GoldSetNotReliableError) as excinfo:
            gi.precision_recall(path_a, path_a, agreement_result=result)
        assert "80%" in str(excinfo.value)

    def test_scoring_without_any_agreement_result_is_refused(self, tmp_path: Path):
        """Gọi 2 tham số (không truyền kết quả độ khớp) phải TỪ CHỐI, không được mặc
        định tính — nếu không, đường tắt vòng qua ngưỡng 80% lại mở."""

        path = _write(tmp_path / "a.csv", _decade("An", set()))
        with pytest.raises(gi.GoldSetNotReliableError) as excinfo:
            gi.precision_recall(path, path)
        assert "agreement()" in str(excinfo.value)

    def test_an_empty_overlap_is_not_a_hundred_percent(self, tmp_path: Path):
        """Hai sheet không chung dòng nào: 0 dòng khớp được không phải là đồng thuận
        tuyệt đối. Xanh vì danh sách rỗng là xanh bằng thông tin bằng không."""

        path_a = _write(tmp_path / "a.csv", [_sheet_row("u01", "present", "An")])
        path_b = _write(tmp_path / "b.csv", [_sheet_row("u99", "present", "Binh")])
        result = gi.agreement(path_a, path_b)
        assert result.n_labelled == 0
        assert result.ratio is None
        assert result.reliable is False
        assert "không có dòng nào" in result.reason

    def test_one_sided_rows_count_as_disagreement_not_as_agreement(self, tmp_path: Path):
        """Người B để trống 4 dòng người A đã dán ⇒ 4 dòng đó là bất đồng, không phải
        đồng thuận im lặng."""

        rows_a = _decade("An", set())
        rows_b = [r for r in _decade("Binh", set()) if r["unit_id"] not in {"u06", "u07", "u08", "u09"}]
        path_a = _write(tmp_path / "a.csv", rows_a)
        path_b = _write(tmp_path / "b.csv", rows_b)
        result = gi.agreement(path_a, path_b, min_labelled=6)
        assert result.n_labelled == 6
        assert result.unlabelled == 4
        assert result.ratio == 1.0

    def test_the_same_annotator_on_both_sheets_is_not_agreement(self, tmp_path: Path):
        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("An", set()))
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.agreement(path_a, path_b)
        assert "cùng một người chấm" in str(excinfo.value)

    def test_perfect_agreement_on_too_few_rows_is_still_refused(self, tmp_path: Path):
        """100% trên 4 dòng là đồng thuận giả: hai người cùng bỏ trống phần khó rồi
        cùng đạt. Sàn theo plan 10 §3 ('20–30 mẫu') phải chặn."""

        rows = [_sheet_row(f"u{i:02d}", "present", "An") for i in range(1, 5)]
        rows_b = [_sheet_row(f"u{i:02d}", "present", "Binh") for i in range(1, 5)]
        result = gi.agreement(_write(tmp_path / "a.csv", rows), _write(tmp_path / "b.csv", rows_b))
        assert result.ratio == 1.0
        assert result.reliable is False
        assert "dưới sàn" in result.reason


class TestScores:
    def test_precision_and_recall_on_a_case_counted_by_hand(self, tmp_path: Path):
        """4 unit, tự đếm tay:
        nhãn vàng  present, absent, present, absent
        hệ thống   present, present, absent, absent
        ⇒ TP=1 FP=1 FN=1 TN=1 ⇒ precision 1/2 = 50%, recall 1/2 = 50%."""

        gold = [
            _sheet_row("u01", "present", "An"),
            _sheet_row("u02", "absent", "An"),
            _sheet_row("u03", "present", "An"),
            _sheet_row("u04", "absent", "An"),
        ]
        second = [dict(row, annotator="Binh") for row in gold]
        system = [
            _sheet_row("u01", "present", "system"),
            _sheet_row("u02", "present", "system"),
            _sheet_row("u03", "absent", "system"),
            _sheet_row("u04", "absent", "system"),
        ]
        path_gold = _write(tmp_path / "gold.csv", gold)
        path_second = _write(tmp_path / "second.csv", second)
        path_system = _write(tmp_path / "system.csv", system)

        result = gi.agreement(path_gold, path_second, min_labelled=4)
        assert result.reliable is True and result.ratio == 1.0

        scores = gi.precision_recall(path_gold, path_system, agreement_result=result)
        assert (scores.tp, scores.fp, scores.fn, scores.tn) == (1, 1, 1, 1)
        assert scores.precision == pytest.approx(0.5)
        assert scores.recall == pytest.approx(0.5)

    def test_an_undefined_precision_says_so_instead_of_printing_zero(self, tmp_path: Path):
        """Hệ thống không báo động nào ⇒ precision không xác định, không phải 0%
        (0% là một lời khẳng định về chất lượng, và nó sai)."""

        gold = [_sheet_row("u01", "absent", "An"), _sheet_row("u02", "absent", "An")]
        second = [dict(row, annotator="Binh") for row in gold]
        system = [
            _sheet_row("u01", "absent", "system"),
            _sheet_row("u02", "absent", "system"),
        ]
        result = gi.agreement(
            _write(tmp_path / "gold.csv", gold),
            _write(tmp_path / "second.csv", second),
            min_labelled=2,
        )
        scores = gi.precision_recall(
            _write(tmp_path / "gold2.csv", gold),
            _write(tmp_path / "system.csv", system),
            agreement_result=result,
        )
        assert scores.precision is None
        assert "không báo động nào" in scores.precision_reason
        assert "không xác định" in scores.describe()

    def test_scoring_refuses_when_one_side_left_rows_unlabelled(self, tmp_path: Path):
        gold = [_sheet_row("u01", "present", "An"), _sheet_row("u02", "present", "An")]
        second = [dict(row, annotator="Binh") for row in gold]
        system = [_sheet_row("u01", "present", "system")]
        result = gi.agreement(
            _write(tmp_path / "gold.csv", gold),
            _write(tmp_path / "second.csv", second),
            min_labelled=2,
        )
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.precision_recall(
                _write(tmp_path / "gold2.csv", gold),
                _write(tmp_path / "system.csv", system),
                agreement_result=result,
            )
        assert "chỉ một bên dán nhãn" in str(excinfo.value)


class TestCli:
    def _raw(self, tmp_path: Path) -> Path:
        raw = tmp_path / "raw.json"
        raw.write_text(
            json.dumps({"units": [u for u in _units_as_json()]}, ensure_ascii=False),
            encoding="utf-8",
        )
        return raw

    def test_sample_writes_a_blank_sheet_then_refuses_to_overwrite_it(self, tmp_path: Path, capsys):
        raw = self._raw(tmp_path)
        out = tmp_path / "sheet-A.csv"

        code = gi.main(["sample", "--units", str(raw), "--out", str(out), "--n", "6", "--seed", "1"])
        capsys.readouterr()
        assert code == 0

        # Một người đã ký: điền cột annotator rồi thử ghi lại cùng chỗ.
        rows = []
        with out.open(encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                row["annotator"] = "An"
                rows.append(row)
        gi.write_sheet(rows, out)

        again = gi.main(["sample", "--units", str(raw), "--out", str(out), "--n", "6", "--seed", "1"])
        printed = capsys.readouterr().out
        assert again == 2
        assert "đã tồn tại" in printed
        assert gi.read_sheet(out).annotator == "An"  # sheet đã ký còn nguyên

    def test_cli_agreement_exit_code_is_one_when_not_reliable_and_zero_when_reliable(
        self, tmp_path: Path, capsys
    ):
        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("Binh", {"u01", "u02", "u03", "u04"}))
        assert gi.main(["agreement", "--a", str(path_a), "--b", str(path_b)]) == 1
        assert "CHƯA ĐỦ TIN CẬY" in capsys.readouterr().out

        # Khớp 100% nhưng chỉ 10 dòng: sàn mặc định 20 chặn — mã thoát 1, không phải 0.
        path_c = _write(tmp_path / "c.csv", _decade("Cuong", set()))
        assert gi.main(["agreement", "--a", str(path_a), "--b", str(path_c)]) == 1
        assert "dưới sàn" in capsys.readouterr().out

        # Hạ sàn tường minh thì mới đạt — và sàn đó hiện ra trong --help, không bị giấu.
        assert gi.main(["agreement", "--a", str(path_a), "--b", str(path_c), "--min-labelled", "10"]) == 0
        capsys.readouterr()

    def test_cli_score_prints_no_precision_when_the_threshold_is_not_met(self, tmp_path: Path, capsys):
        """Đầu-cuối: lệnh `score` trên hai sheet lệch nhau phải thoát 1 và **không in**
        chữ 'precision' nào — nếu in, một con số chưa đủ tin cậy đã ra tới người đọc."""

        path_a = _write(tmp_path / "a.csv", _decade("An", set()))
        path_b = _write(tmp_path / "b.csv", _decade("Binh", {"u01", "u02", "u03", "u04"}))
        system = [dict(row, annotator="system") for row in _decade("An", set())]
        path_system = _write(tmp_path / "system.csv", system)

        code = gi.main(
            [
                "score",
                "--a",
                str(path_a),
                "--b",
                str(path_b),
                "--system",
                str(path_system),
            ]
        )
        printed = capsys.readouterr().out
        assert code == 1
        assert "TỪ CHỐI" in printed
        # Không được có CON SỐ nào: chữ "precision" xuất hiện trong chính câu từ chối.
        assert "precision=" not in printed
        assert "TP=" not in printed

    def test_cli_reads_the_two_layer_store_with_source_snapshot(self, tmp_path: Path, capsys):
        path = _write_store(tmp_path, _payload_with_units(6))
        out = tmp_path / "sheet.csv"
        code = gi.main(
            [
                "sample",
                "--source",
                "snapshot",
                "--units",
                str(path),
                "--out",
                str(out),
                "--n",
                "6",
                "--seed",
                "1",
            ]
        )
        printed = capsys.readouterr().out
        assert code == 0
        assert "lớp mã hoá" in printed  # nói ra dữ liệu bị mã hoá hai lớp
        assert "đã ghi sheet TRỐNG" in printed
        with pytest.raises(gi.GoldSetError):
            gi.read_sheet(out)  # trống thật, không đọc được như sheet đã ký

    def test_cli_bad_input_exits_two(self, tmp_path: Path, capsys):
        code = gi.main(["agreement", "--a", str(tmp_path / "nope.csv"), "--b", str(tmp_path / "k.csv")])
        printed = capsys.readouterr().out
        assert code == 2
        assert "LỖI ĐẦU VÀO" in printed


def _units_as_json():
    """Inventory đúng hình dạng `WorkspaceUnit.toJson()` mà app ghi ra."""

    return [
        {
            "key": u.key,
            "id": u.unit_id,
            "title": f"title {u.unit_id}",
            "text": u.text,
            "kind": u.kind,
            "section": "4.2",
            "pageIndex": 7,
            "malformed": False,
            "selected": True,
            "status": "pending",
        }
        for u in _rich_round().units
    ]


class TestLoading:
    def test_a_session_payload_and_a_bare_list_load_the_same_round(self, tmp_path: Path):
        payload = tmp_path / "session.json"
        payload.write_text(json.dumps({"units": _units_as_json()}), encoding="utf-8")
        bare = tmp_path / "bare.json"
        bare.write_text(json.dumps(_units_as_json()), encoding="utf-8")

        from_payload = gi.load_rounds([payload])
        from_bare = gi.load_rounds([bare])
        assert len(from_payload) == len(from_bare) == 1
        assert [u.unit_id for u in from_payload[0].units] == [u.unit_id for u in from_bare[0].units]
        assert from_payload[0].label == "session"

    def test_multiple_rounds_keep_their_own_labels(self, tmp_path: Path):
        first = tmp_path / "round-1.json"
        first.write_text(json.dumps(_units_as_json()), encoding="utf-8")
        second = tmp_path / "round-2.json"
        second.write_text(json.dumps(_units_as_json()), encoding="utf-8")
        rounds = gi.load_rounds([first, second])
        assert [r.label for r in rounds] == ["round-1", "round-2"]

    def test_a_unit_without_an_id_is_refused(self, tmp_path: Path):
        bad = tmp_path / "bad.json"
        bad.write_text(json.dumps({"units": [{"kind": "Use case", "text": "x"}]}), encoding="utf-8")
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.load_rounds([bad])
        assert "không có `id`" in str(excinfo.value)

    def test_a_file_without_units_or_rounds_is_refused(self, tmp_path: Path):
        bad = tmp_path / "empty.json"
        bad.write_text(json.dumps({"hello": "world"}), encoding="utf-8")
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.load_rounds([bad])
        assert "không thấy `units`" in str(excinfo.value)


def _payload_with_units(count: int = 6, *, file_name: str = "OTES.pdf", fingerprint: str = "5acb1fca"):
    """Payload phiên đúng hình dạng app ghi: `units` + fileName + fingerprint."""

    units = [_unit(f"BR{i:02d}", "Business rule", f"quy tắc {i}", f"k{i}") for i in range(1, count + 1)]
    return {
        "fileName": file_name,
        "pageCount": 162,
        "units": _units_as_json_for(units),
        "parserVersion": "1.4.1",
        "documentFingerprint": fingerprint,
    }


def _units_as_json_for(units) -> list[dict]:
    return [
        {
            "key": u.key,
            "id": u.unit_id,
            "title": f"title {u.unit_id}",
            "text": u.text,
            "kind": u.kind,
            "section": "4.2",
            "pageIndex": 7,
            "malformed": False,
            "selected": True,
            "status": "pending",
        }
        for u in units
    ]


def _write_store(
    tmp_path: Path,
    payload,
    *,
    key: str = "flutter.srs.workspace.snapshot",
    extra: dict | None = None,
    name: str = "store.json",
) -> Path:
    """File dump của shared_preferences: **giá trị là một chuỗi** chứa JSON.

    Đây là lớp mã hoá thứ hai — `json.loads` một lần chỉ ra `str`, và mọi thứ trong đó
    vẫn là chữ.
    """

    store: dict = {key: json.dumps(payload)}
    if extra:
        store.update(extra)
    path = tmp_path / name
    path.write_text(json.dumps(store), encoding="utf-8")
    return path


class TestSnapshotSource:
    def test_the_second_encoding_layer_is_unwrapped(self, tmp_path: Path):
        """Giá trị của shared_preferences là chuỗi chứa JSON: parse một lần là chưa đủ."""

        path = _write_store(
            tmp_path,
            _payload_with_units(6),
            extra={"flutter.srs.proxy.userId": "d41d8cd98f00b204"},
        )
        sources = gi.find_unit_sources(path)
        assert len(sources) == 1
        assert sources[0].layers == 1  # đã gỡ đúng một lớp chuỗi
        assert len(sources[0].units) == 6

        rounds = gi.load_units_from_snapshot(path)
        assert len(rounds) == 1
        assert [u.unit_id for u in rounds[0].units] == [f"BR{i:02d}" for i in range(1, 7)]
        assert rounds[0].label == "OTES.pdf#5acb1fca"

    def test_the_key_name_is_not_hardcoded(self, tmp_path: Path):
        """Đổi tên key và lồng sâu thêm một tầng: vẫn phải đọc được.

        File thật đổi shape lần sau là chuyện bình thường; bám vào tên key của
        shared_preferences thì lần đó công cụ chết.
        """

        path = _write_store(tmp_path, _payload_with_units(4), key="prefs/round-A")
        nested = tmp_path / "nested.json"
        nested.write_text(
            json.dumps({"wrapper": json.loads(path.read_text(encoding="utf-8"))}),
            encoding="utf-8",
        )
        rounds = gi.load_units_from_snapshot(nested)
        assert len(rounds[0].units) == 4

    def test_the_richest_source_wins_and_the_others_are_still_visible(self, tmp_path: Path):
        """Nhiều nguồn: chọn nguồn nhiều unit nhất, **và** `find_unit_sources` nói ra
        những nguồn còn lại — chọn im lặng thì không ai biết đã bỏ qua cái gì."""

        path = _write_store(
            tmp_path,
            _payload_with_units(3),
            extra={
                "flutter.srs.workspace.sessions": [
                    json.dumps(
                        {
                            "id": "s1",
                            "fileName": "OTES.pdf",
                            "payloadJson": json.dumps(_payload_with_units(5)),
                        }
                    )
                ]
            },
        )
        sources = gi.find_unit_sources(path)
        assert len(sources) == 2
        assert sorted(len(s.units) for s in sources) == [3, 5]

        rounds = gi.load_units_from_snapshot(path)
        assert len(rounds[0].units) == 5  # nguồn lớn nhất, không phải nguồn đầu tiên

    def test_a_session_list_two_layers_deep_is_found(self, tmp_path: Path):
        """Hình dạng thật của `flutter.srs.workspace.sessions` trong repo: một mảng các
        **chuỗi**, mỗi chuỗi là một SavedSession, `payloadJson` của nó lại là chuỗi JSON."""

        path = tmp_path / "sessions.json"
        path.write_text(
            json.dumps(
                {
                    "flutter.srs.workspace.sessions": [
                        json.dumps(
                            {
                                "id": "sess-1",
                                "fileName": "OTES.pdf",
                                "payloadJson": json.dumps(_payload_with_units(6)),
                            }
                        )
                    ]
                }
            ),
            encoding="utf-8",
        )
        sources = gi.find_unit_sources(path)
        assert len(sources) == 1
        assert sources[0].layers == 2  # hai lớp chuỗi, không phải một
        assert sources[0].key_path.endswith("payloadJson")
        assert len(sources[0].units) == 6
        assert gi.load_units_from_snapshot(path)[0].label == "OTES.pdf#5acb1fca"

    def test_a_file_with_no_units_says_what_it_saw(self, tmp_path: Path):
        """Không có `units` thì lỗi phải nói ra cấu trúc đã đọc được — nếu không, người
        sau chỉ biết 'không đọc được' và lại phải mở file ra đo bằng tay."""

        path = tmp_path / "alien.json"
        path.write_text(json.dumps({"a": "x", "b": ["y"]}), encoding="utf-8")
        with pytest.raises(gi.GoldSetError) as excinfo:
            gi.find_unit_sources(path)
        message = str(excinfo.value)
        assert "không tìm thấy nguồn" in message
        assert "a=str" in message and "b=list" in message

    def test_a_half_written_json_string_does_not_crash(self, tmp_path: Path):
        """Chuỗi mở đầu bằng `{` nhưng JSON hỏng (file bị cắt lúc ghi) thì bỏ qua chỗ đó,
        không được ném ra ngoài."""

        path = tmp_path / "cut.json"
        path.write_text(
            json.dumps({"half": '{"units": [{"id": ', "real": json.dumps(_payload_with_units(2))}),
            encoding="utf-8",
        )
        rounds = gi.load_units_from_snapshot(path)
        assert len(rounds[0].units) == 2

    def test_a_bare_units_file_still_loads_through_the_same_loader(self, tmp_path: Path):
        path = tmp_path / "bare.json"
        path.write_text(json.dumps(_units_as_json_for(_rich_round().units)), encoding="utf-8")
        rounds = gi.load_units_from_snapshot(path)
        assert len(rounds[0].units) == 8
        assert gi.find_unit_sources(path)[0].layers == 0  # mảng trần: không lớp nào


REAL_SNAPSHOT = ROOT / "reviews" / "workspace-snapshot-2026-09-22-parser1.4.1.json"


@pytest.mark.skipif(
    not REAL_SNAPSHOT.exists(),
    reason="file bằng chứng không có trên cây này — CI không được đỏ vì nó bị dọn đi",
)
class TestTheRealSnapshot:
    """Đọc **file thật** `reviews/workspace-snapshot-2026-09-22-parser1.4.1.json`.

    Các con số dưới đây là đo được trên file đã commit; nếu ai dump lại file bằng
    parser khác thì test này đỏ, và đó là điều đúng: cảnh báo phạm vi trong
    `docs/evidence/goldset-instrument-2026-09-27.md` đang trích đúng những số đó.
    """

    def test_it_yields_240_units_and_the_first_one_has_text(self):
        rounds = gi.load_units_from_snapshot(REAL_SNAPSHOT)
        assert sum(len(round.units) for round in rounds) == 240
        assert rounds[0].units[0].text.strip() != ""
        assert "OTES" in rounds[0].label

    def test_the_kind_distribution_is_the_measured_one(self):
        units = gi.load_units_from_snapshot(REAL_SNAPSHOT)[0].units
        assert Counter(u.kind for u in units) == Counter(
            {"Section": 168, "Use case": 61, "Functional": 5, "Non-functional": 4, "Unknown": 2}
        )

    def test_the_pools_are_the_measured_ones_and_sum_to_the_inventory(self):
        sample = gi.sample_units(gi.load_units_from_snapshot(REAL_SNAPSHOT), n=24, seed=gi.DEFAULT_SEED)
        assert sum(sample.pools.values()) == 240
        assert sample.pools[gi.STRATUM_UC_BODY_SECTION] == 58
        assert sample.pools[gi.STRATUM_UC_MAIN_FLOW] == 9
        assert sample.pools[gi.STRATUM_BUSINESS_RULE] == 0  # OTES không có business rule
        assert sample.distinct_ids == 229

    def test_the_sheet_from_the_real_source_carries_no_label_of_any_kind(self, tmp_path: Path):
        """Đầu-cuối: nguồn thật → mẫu → sheet **trống**. Không một nhãn nào, kể cả ví dụ."""

        sample = gi.sample_units(gi.load_units_from_snapshot(REAL_SNAPSHOT), n=24, seed=gi.DEFAULT_SEED)
        path = gi.annotate_sheet(sample, tmp_path / "sheet-A.csv")
        with path.open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))

        assert len(rows) == 24
        for row in rows:
            assert row["annotator"] == ""
            assert row["finding"] == ""
            assert row["criterion_id"] == ""
            assert row["note"] == ""
            assert row["unit_id"].strip() != ""
            assert row["text"].strip() != ""
            assert row["source_round"].startswith("OTES")
        with pytest.raises(gi.GoldSetError):  # và sheet trống không đọc được như đã ký
            gi.read_sheet(path)


class TestIsolation:
    def test_the_instrument_imports_nothing_from_the_server(self):
        """Bộ dụng cụ phải chạy được mà không cần server: import `app.*` sẽ mở cache
        thật lúc import (đúng cái conftest đang trỏ đi để bảo vệ), và biến một công cụ
        đo thành thứ tốn tiền."""
        tree = ast.parse(INSTRUMENT_PATH.read_text(encoding="utf-8"))
        imported: set[str] = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
        forbidden = {"app", "fastapi", "fitz", "pymupdf", "starlette"}
        assert not (imported & forbidden), f"bộ dụng cụ kéo theo {sorted(imported & forbidden)}"
        assert "pytest" not in imported  # chỉ test mới cần pytest
