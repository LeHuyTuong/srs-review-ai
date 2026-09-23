/// §F.5a/F.5b (rulebook 1.7-draft) — the Format & Layout questions the text
/// extraction can honestly answer: numbered headings forming a hierarchy,
/// and a page number visible at the end of a page.
///
/// Font, size, alignment, line spacing and caption-presence need PDF span
/// metrics or vision — they stay in the "chưa port" table of quality-rules
/// §F.5 until `docmap.py` exposes span/bbox data; faking them from plain
/// text would be worse than silence. Both checks emit only FAILED rows
/// (same contract as `ProjectInfoChecks.sectionOrder`): there is no value
/// in a passed row the UI would only filter out.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';

class FormatLayoutChecks {
  const FormatLayoutChecks();

  // ------------------------------------------------- §F.5a headingNumbering

  /// Only ids the parser resolved to a pure numeric path count as numbered
  /// headings; `SEC-overview` (and every UC/FR id) is out of scope.
  static final RegExp _numberedSectionId = RegExp(r'^SEC-(\d+(?:\.\d+)*)$');

  /// `3.1` cannot exist without `3`, and `4.2.1` without both `4.2` and
  /// `4` — segments are compared per level, never as decimal floats, so
  /// `1.10` after `1.9` stays valid. Two defects are reported: a missing
  /// ancestor level, and the same number string used twice.
  List<DeterministicFinding> headingNumbering(
    List<RequirementItem> requirements,
  ) {
    final firstIdOf = <String, String>{}; // number → first id that used it
    final occurrences = <String>[]; // every numbered heading, in order
    for (final requirement in requirements) {
      final match = _numberedSectionId.firstMatch(requirement.id);
      if (match == null) continue;
      final number = match.group(1)!;
      firstIdOf.putIfAbsent(number, () => requirement.id);
      occurrences.add(number);
    }
    if (occurrences.isEmpty) return const [];

    final findings = <DeterministicFinding>[];
    for (final entry in firstIdOf.entries) {
      if (!entry.key.contains('.')) continue;
      final segments = entry.key.split('.');
      for (var depth = 1; depth < segments.length; depth++) {
        final parent = segments.sublist(0, depth).join('.');
        if (firstIdOf.containsKey(parent)) continue;
        findings.add(
          DeterministicFinding(
            check: CheckId.headingNumbering,
            passed: false,
            severity: Severity.medium,
            subject: 'SEC-${entry.key}',
            message:
                'Mục đánh số "${entry.key}" (${entry.value}) tồn tại nhưng '
                'không thấy mục cha "$parent" — đánh số heading không tạo '
                'thành phân cấp. Đối chiếu mục lục với thân tài liệu.',
          ),
        );
      }
    }

    final counts = <String, int>{};
    for (final number in occurrences) {
      counts[number] = (counts[number] ?? 0) + 1;
    }
    for (final entry in counts.entries) {
      if (entry.value < 2) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.headingNumbering,
          passed: false,
          severity: Severity.medium,
          subject: 'SEC-${entry.key}',
          message:
              'Chuỗi số heading "${entry.key}" xuất hiện ${entry.value} lần '
              'trong các mục SEC — số hiệu không duy nhất, mục lục và '
              'trình bày dễ lẫn. Gộp hoặc đánh lại số hiệu.',
        ),
      );
    }
    return findings;
  }
  // ---------------------------------------------------- §F.5b pageNumbering

  /// Last line of a page that reads as a page number: `12`, `Page 12`,
  /// `Trang 12` (the extractor's footer variants).
  static final RegExp _trailingPageNumber = RegExp(
    r'^(\d{1,3}|(?:page|trang)\s+\d{1,3})$',
    caseSensitive: false,
  );
  static final RegExp _anyDigits = RegExp(r'\d{1,3}');

  /// Same sample gate as §F.2: fewer than 6 pages and there is nothing
  /// recurring to speak of (short documents often skip numbers by choice).
  /// Cover page (index 0) is never expected to carry a number.
  List<DeterministicFinding> pageNumbering(List<String> pageTexts) {
    if (pageTexts.length < 6) return const [];
    final numbers = <int?>[];
    for (var i = 1; i < pageTexts.length; i++) {
      final lines = pageTexts[i]
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      int? number;
      if (lines.isNotEmpty) {
        final last = lines.last;
        if (_trailingPageNumber.hasMatch(last)) {
          number = int.tryParse(_anyDigits.firstMatch(last)!.group(0)!);
        }
      }
      numbers.add(number);
    }

    final findings = <DeterministicFinding>[];
    if (!numbers.any((number) => number != null)) {
      findings.add(
        DeterministicFinding(
          check: CheckId.pageNumbering,
          passed: false,
          severity: Severity.low,
          subject: 'pages',
          message:
              'Không thấy số trang ở dòng cuối của trang nào '
              '(${pageTexts.length - 1} trang sau bìa) — bản in có thể chưa '
              'đánh số trang. Heuristic trên text trích xuất (footer có thể '
              'không nằm ở dòng cuối của text layer) — kiểm tra bằng mắt '
              'trước khi kết luận.',
        ),
      );
      return findings;
    }

    // A printed run counts up; repeats and steps backwards mean the footer
    // belongs to another numbering (or the pages are out of order).
    var regressions = 0;
    for (var i = 1; i < numbers.length; i++) {
      final previous = numbers[i - 1];
      final current = numbers[i];
      if (previous == null || current == null) continue;
      if (current <= previous) regressions++;
    }
    if (regressions >= 3) {
      findings.add(
        DeterministicFinding(
          check: CheckId.pageNumbering,
          passed: false,
          severity: Severity.low,
          subject: 'pages',
          message:
              'Số trang ở dòng cuối trang lặp hoặc giảm $regressions lần '
              '(${numbers.where((number) => number != null).length} trang có '
              'số) — thứ tự/đánh số trang không đơn điệu. Heuristic trên '
              'text trích xuất — kiểm tra bằng mắt.',
        ),
      );
    }
    return findings;
  }

  /// Both §F.5 checks, for callers that hold a parsed document — the same
  /// shape as the other runAll entry points.
  List<DeterministicFinding> runAll(SrsDocument document) => [
    ...headingNumbering(document.requirements),
    ...pageNumbering(document.pageTexts),
  ];
}
