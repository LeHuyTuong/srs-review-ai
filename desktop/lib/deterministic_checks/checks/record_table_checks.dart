/// §G (rulebook 1.8 LOCKED) — the record-table law: bare-digit tables
/// (`01 / 02 / …`) are per-row requirements, not one prose blob.
///
/// This file ports the part of §G that is a FINDING check, without touching
/// the parser: §G.1 (recognise a record table from page text, four
/// conditions, all deterministic) and §G.3 (numbering inside a recognised
/// table must be unique and monotonic — duplicate number → medium, the
/// bare-digit replacement for the `UC04 ×7` catch; jump/reset → low, because
/// a PDF can split one table across pages and make the text layer repeat a
/// run). §G.2 — one unit per row — is a PARSER contract and stays unported
/// until the gold set signs off (§G.4); nothing here changes segmentation.
///
/// Reading `pageTexts` (not parsed units) is deliberate: the bug this law
/// exists for is that the parser SWALLOWS these tables into one `SEC-…`
/// unit, so units are the wrong input — they are the evidence of the crime.
library;

import '../../document_import/models/srs_document.dart';
import '../../requirement_review/models/review_models.dart' show Severity;
import '../models/deterministic_finding.dart';

/// One recognised record table (§G.1): which page it starts on (0-based),
/// and the row numbers in document order. Public because the §G probe and
/// the rule tests both report WHAT was recognised — a check whose detection
/// is invisible cannot be argued about.
class RecordTable {
  RecordTable(this.firstPage, this.firstLine, this.numbers, this.headerText);

  /// 0-based index into `pageTexts`.
  final int firstPage;

  /// 0-based line index of the id-header line within that page's lines.
  final int firstLine;

  /// Bare row numbers, in document order, as written (`'01'` stays `'01'`).
  final List<String> numbers;

  /// The header run, joined — the finding subject.
  final String headerText;

  /// Ledger subject: the header run itself — good enough to point a human at
  /// the right page.
  String get subject =>
      headerText.length <= 60 ? headerText : '${headerText.substring(0, 57)}…';
}

class RecordTableChecks {
  const RecordTableChecks();

  // ------------------------------------------------------------- §G.1 shapes

  /// Header line carrying an identifier column label.
  static final RegExp _idHeader = RegExp(
    r'^(ID|No\.?|Number|Code|Use Case ID|Mã)$',
    caseSensitive: false,
  );

  /// The one header that makes the region an INDEX, not a record table:
  /// a `Page` column points somewhere else, it is not a record.
  static final RegExp _pageHeader = RegExp(
    r'^(Page|Pages|Trang)$',
    caseSensitive: false,
  );

  /// A bare record number: `01`, `2`, `013` — 1–3 digits, zero-pad allowed.
  static final RegExp _bareNumber = RegExp(r'^\d{1,3}$');

  /// How many non-number lines may sit between two row numbers and still
  /// belong to the same table. The extractor prints ONE CELL PER LINE, so
  /// consecutive row numbers are separated by the row's own prose —
  /// measured on the real HisWise text layer: 2–9 lines between numbers
  /// (a 4-line description plus the next row's feature/use-case cells).
  /// 10 is one line of margin over that measurement. Too small truncates
  /// a table (an undercount); too large only overreaches into prose, and
  /// a decreasing number still ends the run, so overreach cannot invent
  /// a duplicate pair.
  static const int _maxCellLines = 10;

  /// How many non-number lines may sit between two row numbers and still
  /// belong to the same table. The extractor prints ONE CELL PER LINE, so
  /// consecutive row numbers are separated by the row's own prose —
  /// measured on the real HisWise text layer: 2–9 lines between numbers
  /// (a 4-line description plus the next row's feature/use-case cells).
  /// 10 is one line of margin over that measurement. Too small truncates
  /// a table (an undercount); too large only overreaches into prose, and
  /// a decreasing number still ends the run, so overreach cannot invent
  /// a duplicate pair.

  /// Footer noise (`Page | 7`, `Page | 7 Page | 8`) — the same shape the
  /// inventory's `isPageFooterOnly` filter treats as junk. A row candidate
  /// that is pure footer is a page boundary, never a record row.
  static final RegExp _footerOnly = RegExp(
    r'^(?:page\s*\|?\s*\d+|\d+\s*\|\s*page)(?:\s+(?:page\s*\|?\s*\d+|\d+\s*\|\s*page))*$',
    caseSensitive: false,
  );

  /// The real HisWise extraction emits the header as separate lines
  /// (`ID` / `Feature` / `Use Case` / `Use Case Description` on page 7), so
  /// "the same line" in §G.1-condition-1 is read as "the same header RUN":
  /// a window of consecutive non-empty lines containing an id label AND a
  /// description-ish label (`Description|Name|Feature|Title|Mô tả|Tên|
  /// Package|Use Case|Table`), with no data row between them.
  static final RegExp _descriptorHeader = RegExp(
    r'(description|name|feature|title|mô tả|tên|package|use case|table)',
    caseSensitive: false,
  );

  // ------------------------------------------------------------- §G.1 engine

  /// Finds record tables in raw page text. Four §G.1 conditions, in order:
  /// (1) a header run with an id column AND a description column;
  /// (2) data rows begin with bare 1–3 digit numbers, non-decreasing;
  /// (3) at least 2 data rows;
  /// (4) NOT an index — a `Page`/`Trang` column header disqualifies.
  List<RecordTable> recordTables(List<String> pageTexts) {
    final tables = <RecordTable>[];
    for (var page = 0; page < pageTexts.length; page++) {
      final lines = pageTexts[page]
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_footerOnly.hasMatch(line)) continue; // page boundary noise
        if (!_idHeader.hasMatch(line)) continue;

        // Condition 1 — gather the header RUN: this line plus following
        // header-ish lines (the extractor splits one visual row into
        // several lines), stopping at the first data row.
        final headerLines = <String>[line];
        var j = i + 1;
        var sawDescriptor = _descriptorHeader.hasMatch(line);
        var sawPageColumn = _pageHeader.hasMatch(line);
        while (j < lines.length &&
            !_bareNumber.hasMatch(lines[j]) &&
            !_footerOnly.hasMatch(lines[j])) {
          headerLines.add(lines[j]);
          if (_descriptorHeader.hasMatch(lines[j])) sawDescriptor = true;
          if (_pageHeader.hasMatch(lines[j])) sawPageColumn = true;
          j++;
        }
        // Condition 4 — an index is a pointer, not a record table.
        if (sawPageColumn) {
          i = j - 1;
          continue;
        }
        // Condition 1 — the id column must be paired with a description.
        if (!sawDescriptor) {
          i = j - 1;
          continue;
        }

        // Conditions 2+3 — collect the numbered rows. The text layer prints
        // one cell per line, so rows are separated by the row's own prose:
        // keep scanning through prose up to _maxCellLines before giving up
        // on the table. A footer ends the run (page boundary); a DECREASING
        // number ends it too — a reset is the next table or a split fragment
        // restarting at 01, not this table.
        final numbers = <String>[];
        var last = -1;
        var pending = 0;
        while (j < lines.length) {
          final row = lines[j];
          if (_footerOnly.hasMatch(row)) break; // table runs to page end
          if (_bareNumber.hasMatch(row)) {
            final value = int.parse(row);
            if (value < last) break; // reset: run boundary, not this table
            last = value;
            numbers.add(row);
            pending = 0;
          } else {
            pending++;
            if (pending > _maxCellLines) break; // prose from here on
          }
          j++;
        }
        if (numbers.length >= 2) {
          tables.add(RecordTable(page, i, numbers, headerLines.join(' ')));
        }
        i = j - 1;
      }
    }
    return tables;
  }

  // -------------------------------------------------------------- §G.3 checks

  /// §G.3.1 — the same number used by two rows in ONE table (amber/medium):
  /// the bare-digit version of the `UC04 ×7` defect that id-prefixed
  /// documents already surface through `duplicateIds`. Per-table on purpose,
  /// never document-wide: two tables each starting at `01` is correct.
  List<DeterministicFinding> recordTableNumbering(List<String> pageTexts) {
    final findings = <DeterministicFinding>[];
    for (final table in recordTables(pageTexts)) {
      final where =
          'page ${table.firstPage + 1} (after the header "${table.subject}")';

      final counts = <String, List<int>>{};
      for (var k = 0; k < table.numbers.length; k++) {
        counts.putIfAbsent(table.numbers[k], () => []).add(k);
      }
      for (final entry in counts.entries) {
        if (entry.value.length < 2) continue;
        findings.add(
          DeterministicFinding(
            check: CheckId.recordTableNumbering,
            passed: false,
            severity: Severity.medium,
            subject: table.subject,
            messageEn:
                'Record table on $where repeats the row number '
                '"${entry.key}" ${entry.value.length} times — bare-digit ids '
                'have no uniqueness check anywhere else, so a duplicated row '
                'silently merges two records. Compare the repeated rows and '
                'renumber.',
            messageVi:
                'Bảng ghi-trường ở $where lặp số hàng "${entry.key}" '
                '${entry.value.length} lần — ID số trần không được kiểm tra '
                'duy nhất ở chỗ nào khác, hai bản ghi bị dính vào nhau một '
                'cách im lặng. So sánh các hàng lặp và đánh lại số.',
          ),
        );
      }

      // §G.3.2 — monotonicity. `_recordTables` already required the run to
      // be non-decreasing to count as one table, so a reset or a jump that
      // ENDS a run is only visible by looking at what follows the break.
      // The text layer cannot tell a real reset from a table split across
      // pages, so this stays low and asks for eyeballing — and a run that
      // ends cleanly at a page boundary is not re-examined (the footer is
      // the boundary, not a defect).
      for (var k = 1; k < table.numbers.length; k++) {
        final previous = int.parse(table.numbers[k - 1]);
        final current = int.parse(table.numbers[k]);
        if (current - previous >= 2) {
          findings.add(
            DeterministicFinding(
              check: CheckId.recordTableNumbering,
              passed: false,
              severity: Severity.low,
              subject: table.subject,
              messageEn:
                  'Record table on $where jumps from "${table.numbers[k - 1]}" '
                  'to "${table.numbers[k]}" — numbering may skip a row or '
                  'resume from another part of the table split across pages. '
                  'Heuristic over extracted text — check visually.',
              messageVi:
                  'Bảng ghi-trường ở $where nhảy từ "${table.numbers[k - 1]}" '
                  'lên "${table.numbers[k]}" — có thể thiếu một hàng, hoặc '
                  'bảng bị tách trang khiến dãy số nối tiếp từ phần khác. '
                  'Heuristic trên text trích xuất — kiểm tra bằng mắt.',
            ),
          );
        }
      }
    }
    return findings;
  }

  /// The §G check, for callers that hold a parsed document — the same shape
  /// as the other runAll entry points. Reads page text only; segmentation
  /// (§G.2) is untouched until the gold set signs the parser port.
  List<DeterministicFinding> runAll(SrsDocument document) =>
      recordTableNumbering(document.pageTexts);
}
