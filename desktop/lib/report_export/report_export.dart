/// Markdown report generator — port of the brief's `exportReport`.
///
/// The brief is adamant that the report is *honest*: it names the mock mode,
/// carries the rubric version, every finding shows its verified quote and the
/// limitations section is not optional. This port keeps all of that.
///
/// Layout (2026-09-11 redesign after user feedback that the flat bullet dump
/// was hard to read): metadata table, coverage table, findings grouped by
/// severity (high first, matching the shell's ordering), inventory as a real
/// table, limitations as bullets. Every honesty element survives verbatim.
library;

import '../deterministic_checks/models/deterministic_finding.dart';
import '../document_import/models/workspace_unit.dart';
import '../requirement_review/models/document_verdict.dart';
import '../requirement_review/models/human_issue.dart';
import '../requirement_review/models/report_language.dart';
import '../requirement_review/models/review_models.dart';
import '../requirement_review/models/review_progress.dart';
import '../requirement_review/models/section_scores.dart';
import '../requirement_review/models/workspace_findings.dart';
import 'report_strings.dart';

// Names what this report was actually scored against. NOT the same thing as
// review-rules/RULEBOOK.md: the app implements a subset of it, so claiming
// "rulebook 1.5" here would assert a conformance the code does not have.
// Bump this string only in the same PR that bumps rubric.json.
const String kRubricLabel = 'SEP490 · app rubric v3 (partial rulebook 1.5)';

/// The same rubric version, as a Vietnamese reader sees it. The stable
/// identifier above is what the JSON twin's `rubric_version` carries and never
/// moves with the language switch; this is only the prose half a human reads in
/// the markdown, HTML and DOCX metadata rows — a version string is still English
/// prose, and leaving it in an otherwise Vietnamese report is the exact
/// half-and-half this option exists to remove.
const String kRubricLabelVi =
    'SEP490 · thang điểm app v3 (rulebook 1.5 một phần)';

/// The honesty contract, as one source of truth for every report twin.
///
/// The markdown used to inline its seven limitation lines and the JSON a
/// near-copy of six — the classic twin drift the R32 audit series kept
/// finding. All three twins (markdown, JSON, HTML) now call this, so a new
/// caveat can be added exactly once and lands everywhere by construction.
List<String> reportLimitations({
  required bool offline,
  ReportLanguage language = ReportLanguage.english,
}) {
  // Every line is a pair. The limitation list is where a half-translated
  // report is easiest to ship by accident — it is eight long sentences at the
  // far edge of the builder, and an English-only one reads as a footnote in
  // another language rather than a mistake.
  final s = ReportStrings(language);
  return [
    offline
        ? s.pick(
            'This is a mock review, not official grading; syllabus thresholds '
                'are provisional.',
            'Đây là lượt chấm mô phỏng, không phải điểm chính thức; các ngưỡng '
                'của thang syllabus chỉ là tạm thời.',
          )
        : s.pick(
            'Online proxy review is not official grading; syllabus thresholds '
                'are provisional.',
            'Lượt chấm trực tuyến qua proxy không phải điểm chính thức; các '
                'ngưỡng của thang syllabus chỉ là tạm thời.',
          ),
    s.pick(
      'No OCR. PDF page images are sent only for eligible pages in a newly '
          'imported PDF during an online run; DOCX, demo, and restored '
          'sessions are text-only. Requirements without an attached image are '
          'assessed from extracted text.',
      'Không OCR. Ảnh trang PDF chỉ được gửi cho những trang đủ điều kiện của '
          'một PDF vừa nhập trong lượt chấm trực tuyến; DOCX, tài liệu demo và '
          'phiên mở lại chỉ có văn bản. Yêu cầu không kèm ảnh được đánh giá từ '
          'văn bản trích xuất.',
    ),
    s.pick(
      'Page-image review is limited to detector-selected PDF pages and does '
          'not imply full visual understanding.',
      'Việc chấm bằng ảnh trang chỉ giới hạn ở các trang PDF được bộ dò chọn '
          'và không có nghĩa là hiểu hết toàn bộ hình ảnh.',
    ),
    s.pick(
      'No resume/checkpoint, and no precision/recall evaluation against a '
          'labelled gold set.',
      'Không có cơ chế chạy tiếp/điểm lưu, và không đo precision/recall trên '
          'một tập dữ liệu chuẩn đã gán nhãn.',
    ),
    s.pick(
      'DOCX page references are logical extraction pages, not rendered '
          'pagination.',
      'Số trang của DOCX là trang trích xuất logic, không phải số trang khi '
          'hiển thị/in ra.',
    ),
    offline
        ? s.pick(
            'Offline mock review sends no model requests; source bytes are '
                'never saved in a saved session.',
            'Lượt chấm mô phỏng ngoại tuyến không gửi yêu cầu nào tới model; '
                'dữ liệu gốc không bao giờ được lưu vào phiên đã lưu.',
          )
        : s.pick(
            'Online PDF reviews may send bounded page images plus requirement '
                'text to the proxy; source bytes are never saved in a saved '
                'session. DOCX, demo, and restored sessions are text-only.',
            'Lượt chấm PDF trực tuyến có thể gửi một số ảnh trang giới hạn '
                'kèm văn bản yêu cầu tới proxy; dữ liệu gốc không bao giờ được '
                'lưu vào phiên đã lưu. DOCX, tài liệu demo và phiên mở lại chỉ '
                'có văn bản.',
          ),
    s.pick(
      'Demo content is synthetic, not measured OTES evidence.',
      'Nội dung demo là dữ liệu tổng hợp, không phải bằng chứng đo được từ OTES.',
    ),
    s.pick(
      'Priority coverage is one document-level verdict (srs-writer criterion '
          '7): it proves the field exists somewhere, never that every '
          'requirement carries one. The vague-wording scan is a conservative '
          'bilingual phrase list (srs-writer skill), not judgment: '
          '"all"/"some" are deliberately unscanned, and criteria needing '
          'meaning (atomic, feasible, correct) stay with the model pass and '
          'the human reviewer.',
      'Độ phủ trường ưu tiên là một kết luận ở cấp tài liệu (tiêu chí 7 của '
          'srs-writer): nó chỉ chứng minh trường này có xuất hiện ở đâu đó, '
          'không chứng minh mọi yêu cầu đều có. Bộ quét câu chữ mơ hồ là một '
          'danh sách cụm từ song ngữ (theo skill srs-writer), không phải phán '
          'đoán: các từ "all"/"some" cố ý không bị quét, và những tiêu chí '
          'cần hiểu nghĩa (atomic, feasible, correct) vẫn thuộc về lượt chấm '
          'của model và người review.',
    ),
  ];
}

/// The rubric version as a reader sees it, for the prose formats.
///
/// The stored value is DATA — a session records what its run was scored
/// against — so a version string this app did not write passes through
/// untouched. Only the label the app wrote itself has a Vietnamese rendering,
/// and it is translated in exactly one place so the markdown, HTML and DOCX
/// twins cannot disagree about which strings follow the language. The JSON twin
/// deliberately keeps the raw value: `rubric_version` is a key a script reads.
String rubricVersionLabel(String raw, ReportStrings s) =>
    raw == kRubricLabel ? s.pick(kRubricLabel, kRubricLabelVi) : raw;

/// The deterministic rows, family-labelled, for every twin.
///
/// One function so the markdown, JSON, HTML and DOCX reports cannot disagree
/// about which family a row belongs to or what they call it — the twin drift
/// the R32 audit series kept finding. The labels are the LOCALIZED ones, so the
/// family name follows the report language while the ledger key (by which the
/// status map is looked up) never does.
List<(String, DeterministicFinding)> reportDeterministicRows({
  required ReportStrings s,
  required List<DeterministicFinding> syllabusFindings,
  required List<DeterministicFinding> referenceFindings,
  required List<DeterministicFinding> blueprintFindings,
}) => [
  for (final finding in syllabusFindings) (s.familyLabel('syllabus'), finding),
  for (final finding in referenceFindings)
    (
      s.familyLabel(
        finding.check == CheckId.diagramAudit
            ? 'diagram audit (vision)'
            : 'reference',
      ),
      finding,
    ),
  for (final finding in blueprintFindings)
    (s.familyLabel('document index'), finding),
];

/// `` `criterion: <id>` `` when the model named one, empty otherwise. One
/// helper so the markdown, HTML and DOCX twins cannot disagree about whether a
/// finding carries a criterion reference or how it is written.
String _criterionSuffix(ReportStrings s, String? criterionId) =>
    criterionId == null || criterionId.isEmpty
    ? ''
    : ' · `${s.criterionRef(criterionId)}`';

String buildMarkdownReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,

  /// The language the whole report is written in. Defaults to English so the
  /// long-standing English assertions in the test suite keep pinning that
  /// rendering; the app always passes the user's choice explicitly (see
  /// `WorkspaceViewModel.exportMarkdown`), which is where the Vietnamese
  /// default lives.
  ReportLanguage language = ReportLanguage.english,

  /// F7/F8/F9 (and friends). These used to live only on the Syllabus tab and
  /// never reached an exported report, so half of what the app could prove for
  /// free was missing from the one artefact a supervisor actually reads.
  List<DeterministicFinding> syllabusFindings = const [],

  /// M2 family: duplicateIds, missingPostcondition, missingActor, and the
  /// contradiction pass. Round 32 review caught both twins omitting these —
  /// the OTES pattern (63/63 use cases without a Postcondition) is exactly
  /// this family, so a report without it hides the most valuable findings
  /// from the one artefact a supervisor reads.
  List<DeterministicFinding> referenceFindings = const [],

  /// Document-index family: duplicated captions, numbering gaps, missing
  /// report parts. Offline and free like the rest, rendered and exported under
  /// their own "document index" family label because their fix lives in the
  /// table of contents, not in a requirement sentence.
  List<DeterministicFinding> blueprintFindings = const [],

  /// Pages that look like diagrams. This is a page count, not an image-review
  /// coverage count; image review is reported separately below.
  int diagramPageCount = 0,

  /// True while original bytes from a newly imported PDF are retained for this
  /// live session. DOCX, demo, and restored sessions are text-only.
  bool imageReviewAvailable = false,

  /// Requirements in the latest run whose successful request carried a PDF page
  /// image. This is a requirement count, not a page or diagram count, and is
  /// deliberately transient rather than persisted with the report input.
  int imageReviewedCount = 0,

  /// Full page-image selection, extraction, and request coverage for the latest
  /// run. This is transient report context and is never persisted with a saved
  /// session.
  PageImageCoverage? imageCoverage,

  /// Reviewer-authored issues (Report tab) — the "con người" rows beside the
  /// model's Findings rows. Each carries its creation timestamp; the Report
  /// tab's source labels name the reviewer the same way.
  List<HumanIssue> humanIssues = const [],

  /// Per-finding triage, keyed by finding id.
  Map<String, FindingStatus> findingStatus = const {},
}) {
  final s = ReportStrings(language);
  final skipped = result?.skipped ?? units.where((u) => !u.selected).length;
  final findings = result?.findings ?? const <FindingRow>[];
  final dropped = result?.droppedIssueCount ?? 0;

  FindingStatus statusFor(String id) => findingStatus[id] ?? FindingStatus.open;
  final reportOffline = result?.mock ?? offline;
  final effectiveImageReviewedCount =
      imageCoverage?.reviewed ?? imageReviewedCount;
  final imageReviewUsed =
      imageReviewAvailable && !reportOffline && effectiveImageReviewedCount > 0;
  final imageReviewCapable = imageReviewAvailable && !reportOffline;

  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now().toUtc();
  final generated =
      '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)} UTC';

  final verdict = computeVerdict([...syllabusFindings, ...referenceFindings]);
  final bySeverity = <Severity, List<FindingRow>>{};
  for (final finding in findings) {
    bySeverity.putIfAbsent(finding.severity, () => []).add(finding);
  }
  const severityOrder = [Severity.high, Severity.medium, Severity.low];
  final severityGlyph = {
    Severity.high: s.pick('🔴 High', '🔴 Nghiêm trọng'),
    Severity.medium: s.pick('🟡 Medium', '🟡 Trung bình'),
    Severity.low: s.pick('🟢 Low', '🟢 Nhẹ'),
  };

  final lines = <String>[
    s.pick('# SRS Review Report', '# Báo cáo đánh giá SRS'),
    '',
    '| | |',
    '|---|---|',
    '| **${s.pick('Document', 'Tài liệu')}** | $fileName |',
    '| **${s.pick('Generated', 'Thời điểm tạo')}** | $generated |',
    '| **${s.pick('Rubric', 'Thang điểm')}** | '
        '${rubricVersionLabel(result?.rubricVersion ?? kRubricLabel, s)} |',
    '| **${s.pick('Mode', 'Chế độ')}** | ${s.mode(reportOffline, short: false)} |',
    '| **${s.pick('Report language', 'Ngôn ngữ báo cáo')}** | '
        '${language.label} |',
    '',
    '> ${s.languageNote}',
    '',
    s.pick('## Coverage', '## Phạm vi đánh giá'),
    '',
    s.pick(
      '| Reviewed | Skipped | Failed | Total units | Unverified dropped |',
      '| Đã chấm | Bỏ qua | Lỗi | Tổng số mục | Trích dẫn bị loại |',
    ),
    '|---:|---:|---:|---:|---:|',
    '| ${result?.reviewed ?? 0} | $skipped | ${result?.failed ?? 0} | '
        '${units.length} | $dropped |',
    '',
  ];

  // The supervisor-facing answer to "which part scores what": the same
  // worst-first rollup the Findings tab shows. Sessions written before
  // scores existed simply have none, and the section is left out rather
  // than printed empty.
  final noTestInput = s.pick(
    '(no test-artifact input in this tool)',
    '(công cụ này chưa có dữ liệu kiểm thử)',
  );
  lines.addAll([
    s.pick(
      '## Verdict (rubric E, 10-point)',
      '## Kết luận (rubric E, thang 10 điểm)',
    ),
    '',
    '**${verdict.display}**',
    '',
    s.pick('| Component | State |', '| Thành phần | Trạng thái |'),
    '|---|---|',
    '| ${s.pick('Floor (7 SRS criteria, 5 pts)', 'Sàn (7 tiêu chí SRS, 5 điểm)')} '
        '| ${s.componentState(verdict.floor)} |',
    '| ${s.pick('Diagrams clean (2 pts)', 'Sơ đồ sạch (2 điểm)')} '
        '| ${s.componentState(verdict.diagram)} |',
    '| ${s.pick('Cross-artifact clean (2 pts)', 'Nhất quán xuyên tài liệu (2 điểm)')} '
        '| ${s.componentState(verdict.crossArtifact)} |',
    '| ${s.pick('Traceability UC→design→test (1 pt)', 'Truy vết UC→thiết kế→kiểm thử (1 điểm)')} '
        '| ${s.componentState(verdict.traceability)} $noTestInput |',
    '| ${s.pick('Deductions −1 per 🔴 ERD/SM/SEQ-CLS row', 'Trừ −1 mỗi dòng 🔴 ERD/SM/SEQ-CLS')} '
        '| ${verdict.deductions} |',
    '',
  ]);
  if (result != null && result.scores.isNotEmpty) {
    final sections = summarizeSections(units: units, result: result);
    if (sections.isNotEmpty) {
      lines.addAll([
        s.pick('## Scores by section', '## Điểm theo mục'),
        '',
        s.pick(
          'Worst average first — start fixing at the top.',
          'Điểm trung bình thấp nhất xếp trước — sửa từ trên xuống.',
        ),
        '',
        s.pick(
          '| Section | Avg /10 | Scored units | To fix | High |',
          '| Mục | TB /10 | Số mục đã chấm | Cần sửa | Nghiêm trọng |',
        ),
        '|---|---:|---:|---:|---:|',
        for (final section in sections)
          '| ${section.section} | '
              '${section.averageScore == null ? '—' : section.averageScore!.toStringAsFixed(1)} | '
              '${section.reviewedCount} | ${section.findingCount} | '
              '${section.highSeverityCount} |',
        '',
      ]);
    }
  }

  final showImageReviewNote =
      diagramPageCount > 0 ||
      imageReviewAvailable ||
      imageReviewedCount > 0 ||
      imageCoverage != null;
  if (showImageReviewNote) {
    final effectiveImageReviewedCount =
        imageCoverage?.reviewed ?? imageReviewedCount;
    final imageReviewNote = reportOffline
        ? '> 🖼️ ${s.pick('**Offline mock mode performed a text-only review.** PDF page images were not sent to the model; any diagram content was assessed from extracted text. Treat "no issues found" as "nothing the text gave away".', '**Chế độ mô phỏng ngoại tuyến chỉ chấm trên văn bản.** Ảnh trang PDF không được gửi cho model; mọi nội dung sơ đồ được đánh giá từ văn bản trích xuất. Hãy hiểu "không thấy lỗi" là "văn bản không để lộ gì".')}'
        : imageReviewUsed
        ? '> 🖼️ ${s.pick('**PDF image review was available, and $effectiveImageReviewedCount requirement(s) were reviewed with page images.** Other requirements were assessed from extracted text alone; diagram content without an attached image was text-only. Treat "no issues found" for those requirements as "nothing the text gave away".', '**Có ảnh trang PDF, và $effectiveImageReviewedCount yêu cầu đã được chấm kèm ảnh trang.** Các yêu cầu còn lại chỉ được đánh giá từ văn bản trích xuất; sơ đồ không kèm ảnh thì chỉ còn văn bản. Với những yêu cầu đó, "không thấy lỗi" nghĩa là "văn bản không để lộ gì".')}'
        : imageReviewCapable
        ? '> 🖼️ ${s.pick('**PDF page images were available, but none were attached to a successful review request.** Any diagram content was therefore text-only; treat "no issues found" as "nothing the text gave away".', '**Có ảnh trang PDF nhưng không ảnh nào được gắn vào một lượt chấm thành công.** Vì vậy mọi nội dung sơ đồ chỉ còn văn bản; hãy hiểu "không thấy lỗi" là "văn bản không để lộ gì".')}'
        : '> 🖼️ ${s.pick('**PDF page images were NOT available for this document or session.** Any diagram content was text-only; review findings came from extracted text. Treat "no issues found" as "nothing the text gave away".', '**Tài liệu hoặc phiên này KHÔNG có ảnh trang PDF.** Mọi nội dung sơ đồ chỉ còn văn bản; lỗi phát hiện được đến từ văn bản trích xuất. Hãy hiểu "không thấy lỗi" là "văn bản không để lộ gì".')}';
    lines
      ..add(imageReviewNote)
      ..add('');
  }

  if (imageCoverage != null) {
    final coverage = imageCoverage;
    lines
      ..add(s.pick('## PDF page-image coverage', '## Phạm vi ảnh trang PDF'))
      ..add('')
      ..add(
        s.pick(
          '| Candidates | Extracted | Image-reviewed | Text-only/skipped | Image failures |',
          '| Trang ứng viên | Đã trích ảnh | Đã chấm bằng ảnh | Chỉ văn bản/bỏ qua | Ảnh lỗi |',
        ),
      )
      ..add('|---:|---:|---:|---:|---:|')
      ..add(
        '| ${coverage.candidates} | ${coverage.extracted} | '
        '${coverage.reviewed} | ${coverage.skipped} | ${coverage.failed} |',
      )
      ..add('')
      ..add(
        s.pick(
          '`Text-only/skipped` includes ordinary text-only requirements and '
              'requirements whose image path was deferred or failed; `Image failures` '
              'counts image preparation or image-bearing request failures, not ordinary '
              'text-only requirements.',
          '`Chỉ văn bản/bỏ qua` gồm các yêu cầu vốn chỉ có văn bản và các yêu '
              'cầu mà đường ảnh bị hoãn hoặc lỗi; `Ảnh lỗi` đếm lỗi khi chuẩn bị ảnh '
              'hoặc khi gọi kèm ảnh, không tính các yêu cầu chỉ có văn bản.',
        ),
      )
      ..add('');

    final reasonEntries = coverage.reasons.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (reasonEntries.isEmpty) {
      lines.add(
        s.pick('Image-review reasons: none', 'Lý do xem ảnh: không có'),
      );
    } else {
      final reasonTokens = reasonEntries
          .map((entry) => 'reason=${entry.key}=${entry.value}')
          .join(', ');
      lines.add(
        '${s.pick('Image-review reasons', 'Lý do xem ảnh')}: $reasonTokens',
      );
    }
    lines.add('');

    final decisionEntries = coverage.decisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (decisionEntries.isEmpty) {
      lines.add(
        s.pick('Image-review decisions: none', 'Quyết định xem ảnh: không có'),
      );
    } else {
      final decisionTokens = decisionEntries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      lines.add(
        '${s.pick('Image-review decisions', 'Quyết định xem ảnh')}: '
        '$decisionTokens',
      );
    }
    lines.add('');
  }

  // A run that never finished (cancelled, killed by quota/auth) or returned
  // nothing must say so in plain words. Coverage numbers alone, printed next
  // to a full inventory, read as "everything was reviewed" — the exact
  // confusion this report exists to prevent.
  if (result != null &&
      (result.outcome != 'done' || result.reviewed == 0 || result.failed > 0)) {
    final ended = s.runOutcome(result.outcome);
    final failedNote = result.failed > 0
        ? s.pick(
            ' ${result.failed} selected unit(s) errored and were NOT reviewed.',
            ' ${result.failed} mục đã chọn bị lỗi và KHÔNG được chấm.',
          )
        : '';
    lines
      ..add(
        s.pick(
          '> ⚠️ **The last review run $ended — only ${result.reviewed} '
              'selected unit(s) returned results.$failedNote** Units are marked '
              '`reviewed` only where the run returned a result; the rest are '
              '`pending` or `failed`, and nothing was assessed for them.',
          '> ⚠️ **Lượt chấm gần nhất $ended — chỉ ${result.reviewed} mục đã '
              'chọn trả về kết quả.$failedNote** Mục chỉ được đánh dấu `đã '
              'chấm` khi lượt chấm thực sự trả kết quả; số còn lại đang chờ '
              'hoặc lỗi, và không được đánh giá gì.',
        ),
      )
      ..add('');
  }

  // Both offline families share the table: syllabus (F7/F8/F9) and reference
  // (M2) are separate engines on the same data path, and the Findings tab
  // renders them under different headings — the report must not merge them
  // silently, so each row carries its family label.
  final allDeterministic = reportDeterministicRows(
    s: s,
    syllabusFindings: syllabusFindings,
    referenceFindings: referenceFindings,
    blueprintFindings: blueprintFindings,
  );
  if (allDeterministic.isNotEmpty) {
    final failing = allDeterministic
        .where((entry) => !entry.$2.passed)
        .toList(growable: false);
    lines
      ..add(
        '${s.pick('## Deterministic checks', '## Kiểm tra bằng luật')} '
        '(${allDeterministic.length})',
      )
      ..add('')
      ..add(
        '${s.pick('Offline rule checks — no model, zero tokens, run the moment the document is imported.', 'Kiểm tra bằng luật ngoại tuyến — không gọi model, không tốn token, chạy ngay khi nhập tài liệu.')} '
        '${s.pick('"syllabus" rows come from the SEP490 rubric (F7/F8/F9) plus the srs-writer quality scan; "reference (M2)" rows are the consistency checks (duplicate ids, missing postconditions, cross-artifact names).', 'Nhóm "Syllabus" đến từ thang SEP490 (F7/F8/F9) và bộ quét chất lượng của srs-writer; nhóm "Mùi nhất quán (M2)" là các kiểm tra nhất quán (mã trùng, thiếu hậu điều kiện, tên thực thể khác nhau giữa các mục).')} '
        '${s.pick('The "diagram audit (vision)" family is the exception to the offline claim above: those rows come from the two-call vision audit of detector-selected pages (sds-reviewer steps 4-6).', 'Nhóm "Chấm sơ đồ (vision)" là ngoại lệ của chữ "ngoại tuyến" ở trên: các dòng đó đến từ hai lượt chấm ảnh trên những trang được bộ dò chọn (sds-reviewer bước 4-6).')} '
        '${failing.isEmpty ? s.pick('All checks passed.', 'Tất cả kiểm tra đều đạt.') : s.pick('${failing.length} of ${allDeterministic.length} need attention.', '${failing.length}/${allDeterministic.length} mục cần xử lý.')}',
      )
      ..add('')
      ..add(
        s.pick(
          '| Family | Check | Subject | Result | Status | Detail |',
          '| Nhóm | Kiểm tra | Đối tượng | Kết quả | Trạng thái | Chi tiết |',
        ),
      )
      ..add('|---|---|---|---|---|---|');
    for (final (family, finding) in allDeterministic) {
      // Status is ledger state, not re-derivable from the document: it
      // comes from the Verifier's re-run map (sds-reviewer discipline
      // "the old ledger is a contract"). Passing rows never had a
      // status — only failing rows live in the ledger.
      final status = finding.passed
          ? '—'
          : s.findingStatusLabel(statusFor(finding.ledgerKey));
      lines.add(
        '| $family | ${s.checkLabel(finding.check)} | '
        '${finding.subject ?? s.pick('whole document', 'toàn tài liệu')} | '
        '${finding.passed ? s.passedFailed(true) : '**${s.severityLabel(finding.severity)}**'} '
        '| $status | '
        '${finding.messageFor(language).replaceAll('|', '\\|')} |',
      );
    }
    lines.add('');
  }

  if (findings.isEmpty) {
    // Three different truths hide behind "no findings": nothing has run yet,
    // a run finished and verified nothing worth reporting, or a run returned
    // nothing at all. Each owes the reader a different sentence.
    final message = result == null
        ? s.pick(
            '*No findings yet — run a review to populate this section.*',
            '*Chưa có lỗi nào — hãy chạy một lượt chấm để có dữ liệu cho mục này.*',
          )
        : result.reviewed > 0
        ? s.pick(
            '*The run reviewed ${result.reviewed} unit(s) and verified no issues worth reporting.*',
            '*Lượt chấm đã chấm ${result.reviewed} mục và không có lỗi nào đáng báo cáo.*',
          )
        : s.pick(
            '*No findings — no unit was successfully reviewed. See the warning above.*',
            '*Không có lỗi — không mục nào được chấm thành công. Xem cảnh báo ở trên.*',
          );
    lines
      ..add(s.pick('## Findings', '## Lỗi phát hiện'))
      ..add('')
      ..add(message)
      ..add('');
  } else {
    final accepted = findings
        .where((finding) => statusFor(finding.id) == FindingStatus.fixed)
        .length;
    final dismissed = findings
        .where((finding) => statusFor(finding.id) == FindingStatus.disputed)
        .length;

    lines.add(
      '${s.pick('## Findings', '## Lỗi phát hiện')} (${findings.length})',
    );
    // Task Báo cáo tổng hợp: every issue names its reviewer. Model rows
    // name the model that answered plus the prompt/rubric version; human
    // rows live in the section below with their own timestamps.
    final modelLabel = result == null
        ? s.pick('not run', 'chưa chạy')
        : (result.model ??
              (result.mock
                  ? s.pick('offline mock run', 'lượt mô phỏng ngoại tuyến')
                  : s.pick(
                      'proxy run, model not recorded',
                      'lượt chạy qua proxy, không ghi nhận model',
                    )));
    lines
      ..add('')
      ..add(
        '${s.pick('Reviewer', 'Người chấm')}: AI · $modelLabel · '
        '${s.pick('rubric', 'thang điểm')} '
        '${rubricVersionLabel(result?.rubricVersion ?? kRubricLabel, s)} · '
        '${s.pick('human issues', 'lỗi do người ghi')}: ${humanIssues.length}',
      );
    if (accepted > 0 || dismissed > 0) {
      lines
        ..add('')
        ..add(
          s.pick(
            'Triage: $accepted accepted · $dismissed dismissed · ${findings.length - accepted - dismissed} still open.',
            'Phân loại: $accepted đã sửa · $dismissed phản hồi là sai · ${findings.length - accepted - dismissed} còn để ngỏ.',
          ),
        );
    }
    for (final severity in severityOrder) {
      final group = bySeverity[severity] ?? const <FindingRow>[];
      if (group.isEmpty) continue;
      lines
        ..add('')
        ..add('### ${severityGlyph[severity]} (${group.length})');
      for (final finding in group) {
        lines
          ..add('')
          ..add('#### ${finding.requirementId} · ${finding.title}')
          ..add('')
          ..add(
            '`${s.pick('page', 'trang')} ${finding.pageIndex + 1}` · '
            '`${s.verificationLabel(finding.issue.verification)}` · '
            '`${s.findingStatusLabel(statusFor(finding.id))}`'
            // Which rubric row the model was answering when it raised this.
            // Printed only when the model named one: an id a user added to the
            // criteria list is the only thing that traces the finding back to
            // the wording they wrote, and it is deliberately NOT translated.
            '${_criterionSuffix(s, finding.issue.criterionId)}',
          )
          ..add('')
          ..addAll(finding.quote.split('\n').map((line) => '> $line'))
          ..add('')
          ..add('**${s.pick('Suggestion', 'Gợi ý')}.** ${finding.suggestion}');
      }
    }
    lines.add('');
  }

  lines
    ..add('${s.pick('## Inventory', '## Danh mục tài liệu')} (${units.length})')
    ..add('')
    ..add(
      s.pick(
        '| ID | Requirement | Kind | Page | Status |',
        '| Mã | Yêu cầu | Loại | Trang | Trạng thái |',
      ),
    )
    ..add('|---|---|---|---|---|');
  for (final unit in units) {
    final status = unit.malformed
        ? '${s.unitStatusLabel(unit.status.name)} · '
              '${s.pick('MALFORMED', 'LỖI ĐỊNH DẠNG')}'
        : s.unitStatusLabel(unit.status.name);
    lines.add(
      '| ${unit.id} | ${unit.title.replaceAll('|', '\\|')} | '
      '${s.unitKindLabel(unit.kind)} | ${unit.pageIndex + 1} | $status |',
    );
  }

  lines
    ..add('')
    ..add(
      '${s.pick('## Human-reported issues', '## Lỗi do người review ghi')} '
      '(${humanIssues.length})',
    )
    ..add('')
    ..add(
      s.pick(
        'Entered by a reviewer in the app — not model output.',
        'Do người review nhập trong ứng dụng — không phải kết quả của model.',
      ),
    )
    ..add('')
    ..add(
      s.pick(
        '| When (UTC) | Severity | Section | Title | Detail |',
        '| Thời điểm (UTC) | Mức độ | Vị trí | Tiêu đề | Chi tiết |',
      ),
    )
    ..add('|---|---|---|---|---|');
  for (final issue in humanIssues) {
    final stamp = issue.createdAt.toUtc().toIso8601String();
    final detail = issue.detail.isEmpty ? '—' : issue.detail;
    lines.add(
      '| $stamp | ${s.severityLabel(issue.severity)} | '
      '${issue.section ?? '—'} | ${issue.title.replaceAll('|', '\\|')} | '
      '${detail.replaceAll('|', '\\|')} |',
    );
  }

  lines
    ..add('')
    ..add(
      s.pick('## Limitations & future work', '## Giới hạn & hướng tiếp theo'),
    )
    ..add('')
    ..addAll([
      for (final limitation in reportLimitations(
        offline: reportOffline,
        language: language,
      ))
        '- $limitation',
    ]);
  return lines.join('\n');
}

/// Severity ordering helper kept next to its only consumer.
int severityWeight(Severity severity) => severity.weight;

/// JSON twin of [buildMarkdownReport] — same inputs, same numbers.
///
/// The brief's Output row demands "ledger.md + JSON + share sheet": markdown
/// is for the supervisor, JSON is for a server or web tool to read later
/// against one shared schema. Because both builders receive identical
/// arguments, every count in the prose (reviewed/skipped/failed, triage
/// split, deterministic checks) can be recomputed from this payload and
/// cross-checked against the markdown — goal §5 rule 3 enforced by code,
/// not by eye.
///
/// Additive-only schema: consumers must treat unknown keys as ignorable, so
/// adding fields later never breaks an older reader (same contract rule as
/// contracts/review.schema.json v1.0.0).
Map<String, dynamic> buildJsonReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,

  /// The language the report is written in. Only the human-readable VALUES
  /// follow it (`message`, `limitations`, `report_language`); the KEYS and the
  /// enum tokens a consumer filters on (`severity`, `status`, `family`) stay
  /// stable, because a JSON twin whose machine contract moved with a UI switch
  /// would break every reader that parses it.
  ReportLanguage language = ReportLanguage.english,
  List<DeterministicFinding> syllabusFindings = const [],
  List<DeterministicFinding> referenceFindings = const [],
  List<DeterministicFinding> blueprintFindings = const [],
  int diagramPageCount = 0,
  bool imageReviewAvailable = false,
  int imageReviewedCount = 0,
  PageImageCoverage? imageCoverage,
  Map<String, FindingStatus> findingStatus = const {},

  /// Reviewer-authored issues (Report tab) — additive-only schema, so older
  /// readers ignore an unknown `human_issues` key by contract.
  List<HumanIssue> humanIssues = const [],
}) {
  final s = ReportStrings(language);
  final findings = result?.findings ?? const <FindingRow>[];
  FindingStatus statusFor(String id) => findingStatus[id] ?? FindingStatus.open;
  // The run's own mock flag outranks the current toggle, exactly as the
  // markdown twin does — a report describes the run that happened, not the
  // setting at the moment of export.
  final reportOffline = result?.mock ?? offline;

  return {
    'schema': 'srs-review/report',
    'x-schema-version': '1.0.0',
    'report_language': language.wire,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'document': {
      'file_name': fileName,
      'rubric_version': result?.rubricVersion ?? kRubricLabel,
      'mode': reportOffline ? 'offline_mock' : 'online_proxy',
    },
    'coverage': {
      // Markdown twin: the Coverage table row. Same arithmetic, same source.
      'reviewed': result?.reviewed ?? 0,
      'skipped': result?.skipped ?? units.where((u) => !u.selected).length,
      'failed': result?.failed ?? 0,
      'total_units': units.length,
      'unverified_dropped': result?.droppedIssueCount ?? 0,
      // Round 32 audit: the markdown prints a plain-words warning when the
      // run ended in anything but a clean full completion; the JSON needs
      // the structured counterpart so a consumer can flag the same rows.
      if (result != null) 'run_outcome': result.outcome,
      if (imageCoverage != null)
        'page_images': {
          'candidates': imageCoverage.candidates,
          'extracted': imageCoverage.extracted,
          'reviewed': imageCoverage.reviewed,
          'skipped': imageCoverage.skipped,
          'failed': imageCoverage.failed,
        },
      // Round 32 audit — these inputs drive the markdown honesty notes (the
      // "text-only review" callout and the diagram-page count), so a JSON
      // consumer must be able to reconstruct them instead of trusting a
      // silent "no issues" section. Absent ≠ zero: keys appear only when
      // the markdown would print the corresponding note.
      if (diagramPageCount > 0) 'diagram_pages': diagramPageCount,
      if (imageReviewAvailable || imageReviewedCount > 0)
        'image_review': {
          'available': imageReviewAvailable,
          'reviewed_requirements': imageReviewedCount,
        },
    },
    'scores': {
      // Round 32 audit: the first JSON cut labeled result.scores entries as
      // sections, but that map is keyed by UNIT key with the raw per-unit
      // score — a different number than the markdown's "Scores by section"
      // table, which uses summarizeSections (per-section averages, worst
      // first). The JSON now consumes the exact same rollup, so the two
      // twins print the same table by construction.
      'sections': [
        for (final section
            in (result == null || units.isEmpty
                ? const <SectionScore>[]
                : summarizeSections(units: units, result: result)))
          {
            'section': section.section,
            'average_score': section.averageScore == null
                ? null
                : double.parse(section.averageScore!.toStringAsFixed(1)),
            'reviewed_count': section.reviewedCount,
            'finding_count': section.findingCount,
            'high_severity_count': section.highSeverityCount,
          },
      ],
    },
    'findings': [
      for (final finding in findings)
        {
          'id': finding.id,
          'requirement_id': finding.requirementId,
          'page_index': finding.pageIndex,
          'severity': finding.severity.name,
          'title': finding.title,
          // The criterion the model was answering — a row id from the editable
          // criteria list, null when it named none. A lookup key, so it stays
          // untranslated like `severity` and `status` beside it.
          'criterion_id': finding.issue.criterionId,
          'verification': finding.issue.verification.name,
          'status': statusFor(finding.id).name,
          'quote': finding.quote,
          'suggestion': finding.suggestion,
        },
    ],
    'verdict': computeVerdict([
      ...syllabusFindings,
      ...referenceFindings,
    ]).toJson(),
    'human_issues': [for (final issue in humanIssues) issue.toJson()],
    'deterministic_checks': [
      for (final finding in syllabusFindings)
        {
          'family': 'syllabus',
          'check': finding.check.wire,
          'subject': finding.subject,
          'passed': finding.passed,
          'severity': finding.severity.name,
          'message': finding.messageFor(language),
          // Round 26's UNV upstream flag: a JSON consumer filters on this
          // instead of re-parsing messages.
          'requires_vision_evidence': finding.requiresVisionEvidence,
          // Ledger status per the Verifier's re-run map; passing rows
          // carry none (null), only failing rows live in the ledger.
          'status': finding.passed ? null : statusFor(finding.ledgerKey).name,
        },
      for (final finding in referenceFindings)
        {
          'family': 'reference',
          'check': finding.check.wire,
          'subject': finding.subject,
          'passed': finding.passed,
          'severity': finding.severity.name,
          'message': finding.messageFor(language),
          'requires_vision_evidence': finding.requiresVisionEvidence,
          'status': finding.passed ? null : statusFor(finding.ledgerKey).name,
        },
      for (final finding in blueprintFindings)
        {
          'family': 'document index',
          'check': finding.check.wire,
          'subject': finding.subject,
          'passed': finding.passed,
          'severity': finding.severity.name,
          'message': finding.messageFor(language),
          'requires_vision_evidence': finding.requiresVisionEvidence,
          'status': finding.passed ? null : statusFor(finding.ledgerKey).name,
        },
    ],
    'inventory': [
      for (final unit in units)
        {
          'id': unit.id,
          'kind': s.unitKindLabel(unit.kind),
          'page_index': unit.pageIndex,
          'status': unit.status.name,
          'malformed': unit.malformed,
        },
    ],
    'limitations': [
      // The same honesty contract the markdown carries, from one shared
      // source — see reportLimitations. The DOCX pagination and demo-content
      // caveats the first JSON cut dropped are now structurally impossible
      // to omit.
      ...reportLimitations(offline: reportOffline, language: language),
    ],
  };
}
