/// HTML report dashboard — the third twin of the export family.
///
/// The brief's Report row asks for a *dashboard*, not prose: a supervisor
/// opens one file in a browser and sees coverage, score bars, triaged
/// findings, and the deterministic ledger without reading 300 lines of
/// markdown. This builder takes the exact same inputs as the markdown and
/// JSON twins (their R32 audit lesson applies: one data source, rendered
/// three ways — the numbers agree by construction, and honesty notes that
/// markdown prints appear here under identical conditions).
///
/// Self-contained by rule: inline CSS only, zero external resources, opens
/// from file:// on any machine, works inside the OS share sheet's HTML
/// preview. And because every string it renders can originate from an
/// untrusted user document, ALL interpolation goes through [_esc] — the
/// report must never execute the document it reviews.
library;

import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/human_issue.dart';
import '../../../data/models/report_language.dart';
import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import 'document_verdict.dart';
import 'report_export.dart';
import 'report_strings.dart';
import 'section_scores.dart';
import 'workspace_findings.dart';
import 'workspace_unit.dart';

String _statusClass(FindingStatus s) => switch (s) {
  FindingStatus.open => 'bad',
  FindingStatus.fixed => 'amber',
  FindingStatus.verified => 'ok',
  FindingStatus.pendingVision => 'amber',
  FindingStatus.disputed => '',
};

/// `_CheckGroup.severity` is the enum's NAME (it is part of the group's
/// identity, so it must not follow the language); the cell it lands in is
/// prose, so this is where the name becomes a word the reader understands.
String _localizedSeverity(ReportStrings s, String severity) =>
    switch (severity) {
      'high' => s.severityLabel(Severity.high),
      'medium' => s.severityLabel(Severity.medium),
      'low' => s.severityLabel(Severity.low),
      _ => severity,
    };

String _esc(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// One row of the grouped deterministic summary: everything that shares a
/// family, check, pass-state, severity, and message shape collapses into
/// it, carrying the list of affected subjects.
class _CheckGroup {
  const _CheckGroup({
    required this.family,
    required this.label,
    required this.passed,
    required this.severity,
    required this.template,
    required this.vision,
  });

  final String family;
  final String label;
  final bool passed;
  final String severity;
  final String template;
  final bool vision;

  @override
  bool operator ==(Object other) =>
      other is _CheckGroup &&
      other.family == family &&
      other.label == label &&
      other.passed == passed &&
      other.severity == severity &&
      other.template == template &&
      other.vision == vision;

  @override
  int get hashCode =>
      Object.hash(family, label, passed, severity, template, vision);
}

String buildHtmlReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,
  List<DeterministicFinding> syllabusFindings = const [],
  List<DeterministicFinding> referenceFindings = const [],
  List<DeterministicFinding> blueprintFindings = const [],
  int diagramPageCount = 0,
  bool imageReviewAvailable = false,
  int imageReviewedCount = 0,
  PageImageCoverage? imageCoverage,
  Map<String, FindingStatus> findingStatus = const {},

  /// Reviewer-authored issues (Report tab) — rendered in their own section
  /// so the shared-with-link dashboard carries the human side too.
  List<HumanIssue> humanIssues = const [],

  /// The language the dashboard is written in. See [buildMarkdownReport] for
  /// why the builder default stays English while the app passes the user's
  /// choice explicitly.
  ReportLanguage language = ReportLanguage.english,
}) {
  final s = ReportStrings(language);
  // Same effective-mode rule as both twins: the run's own mock flag outranks
  // the toggle at export time.
  final reportOffline = result?.mock ?? offline;
  final findings = result?.findings ?? const <FindingRow>[];
  final skipped = result?.skipped ?? units.where((u) => !u.selected).length;
  FindingStatus statusFor(String id) => findingStatus[id] ?? FindingStatus.open;
  final now = DateTime.now().toUtc();
  final generated = now.toIso8601String();
  final effectiveImageReviewedCount =
      imageCoverage?.reviewed ?? imageReviewedCount;
  final imageReviewUsed =
      imageReviewAvailable && !reportOffline && effectiveImageReviewedCount > 0;
  final imageReviewCapable = imageReviewAvailable && !reportOffline;

  final out = StringBuffer()
    ..write(
      '<!DOCTYPE html>\n<html lang="${language.wire}">\n<head>\n<meta charset="utf-8">',
    )
    ..write(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    )
    ..write(
      '<title>${s.pick('SRS Review', 'Đánh giá SRS')} — '
      '${_esc(fileName)}</title>',
    )
    ..write('<style>$_css</style>\n</head>\n<body>\n');

  // ── Header ────────────────────────────────────────────────────────────
  final modeChip = reportOffline
      ? '<span class="chip amber">${_esc(s.mode(true, short: false))}</span>'
      : '<span class="chip blue">${_esc(s.mode(false, short: false))}</span>';
  out.write(
    '<header><h1>${_esc(s.pick('SRS Review Report', 'Báo cáo đánh giá SRS'))}</h1>'
    '<p class="meta">${_esc(fileName)} · '
    '${_esc(rubricVersionLabel(result?.rubricVersion ?? kRubricLabel, s))}'
    ' · ${_esc(s.pick('generated', 'tạo lúc'))} ${_esc(generated)}</p>'
    '<p>$modeChip</p>'
    '<p class="meta">${_esc(s.languageNote)}</p></header>\n',
  );

  // ── Coverage cards ────────────────────────────────────────────────────
  out.write(
    '<h2>${_esc(s.pick('Coverage', 'Phạm vi đánh giá'))}</h2>\n'
    '<div class="cards">',
  );
  void card(String label, String value, [String tone = '']) {
    out.write(
      '<div class="card"><div class="num $tone">$value</div>'
      '<div class="lbl">$label</div></div>',
    );
  }

  card(s.pick('Reviewed', 'Đã chấm'), '${result?.reviewed ?? 0}');
  card(
    s.pick('Failed', 'Lỗi'),
    '${result?.failed ?? 0}',
    (result?.failed ?? 0) > 0 ? 'red' : '',
  );
  card(s.pick('Skipped', 'Bỏ qua'), '$skipped');
  card(s.pick('Total units', 'Tổng số mục'), '${units.length}');
  card(
    s.pick('Unverified dropped', 'Trích dẫn bị loại'),
    '${result?.droppedIssueCount ?? 0}',
    (result?.droppedIssueCount ?? 0) > 0 ? 'amber' : '',
  );
  out.write('</div>\n');

  // ── Honesty banners (same conditions as the markdown's notes) ─────────
  if (result != null &&
      (result.outcome != 'done' || result.reviewed == 0 || result.failed > 0)) {
    final ended = s.runOutcome(result.outcome);
    final failedNote = result.failed > 0
        ? s.pick(
            ' ${result.failed} selected unit(s) errored and were NOT reviewed.',
            ' ${result.failed} mục đã chọn bị lỗi và KHÔNG được chấm.',
          )
        : '';
    out.write(
      '<div class="banner red"><b>${_esc(s.pick('The last review run $ended — only ${result.reviewed} selected unit(s) returned results.$failedNote', 'Lượt chấm gần nhất $ended — chỉ ${result.reviewed} mục đã chọn trả về kết quả.$failedNote'))}</b> '
      '${_esc(s.pick('Units are marked reviewed only where the run returned a result; the rest are pending or failed, and nothing was assessed for them.', 'Mục chỉ được đánh dấu đã chấm khi lượt chấm trả kết quả; số còn lại đang chờ hoặc lỗi, và không được đánh giá gì.'))}</div>\n',
    );
  }
  final showImageReviewNote =
      diagramPageCount > 0 ||
      imageReviewAvailable ||
      imageReviewedCount > 0 ||
      imageCoverage != null;
  if (showImageReviewNote) {
    final note = reportOffline
        ? s.pick(
            '<b>Offline mock mode performed a text-only review.</b> PDF page images were not sent to the model; any diagram content was assessed from extracted text. Treat "no issues found" as "nothing the text gave away".',
            '<b>Chế độ mô phỏng ngoại tuyến chỉ chấm trên văn bản.</b> Ảnh trang PDF không được gửi cho model; mọi nội dung sơ đồ được đánh giá từ văn bản trích xuất. Hãy hiểu "không thấy lỗi" là "văn bản không để lộ gì".',
          )
        : imageReviewUsed
        ? s.pick(
            '<b>PDF image review was available, and $effectiveImageReviewedCount requirement(s) were reviewed with page images.</b> Other requirements were assessed from extracted text alone.',
            '<b>Có ảnh trang PDF, và $effectiveImageReviewedCount yêu cầu đã được chấm kèm ảnh trang.</b> Các yêu cầu còn lại chỉ được đánh giá từ văn bản trích xuất.',
          )
        : imageReviewCapable
        ? s.pick(
            '<b>PDF page images were available, but none were attached to a successful review request.</b> Any diagram content was therefore text-only.',
            '<b>Có ảnh trang PDF nhưng không ảnh nào được gắn vào một lượt chấm thành công.</b> Vì vậy mọi nội dung sơ đồ chỉ còn văn bản.',
          )
        : s.pick(
            '<b>PDF page images were NOT available for this document or session.</b> Any diagram content was text-only; review findings came from extracted text.',
            '<b>Tài liệu hoặc phiên này KHÔNG có ảnh trang PDF.</b> Mọi nội dung sơ đồ chỉ còn văn bản; lỗi phát hiện được đến từ văn bản trích xuất.',
          );
    out.write('<div class="banner grey">🖼️ $note</div>\n');
    if (diagramPageCount > 0) {
      out.write(
        '<p class="meta">${_esc(s.pick('Diagram-like pages detected', 'Số trang trông như có sơ đồ'))}: '
        '$diagramPageCount</p>\n',
      );
    }
  }
  if (imageCoverage != null) {
    final c = imageCoverage;
    out.write(
      '<h3>${_esc(s.pick('PDF page-image coverage', 'Phạm vi ảnh trang PDF'))}</h3>'
      '<div class="tscroll"><table>'
      '<tr><th>${_esc(s.pick('Candidates', 'Trang ứng viên'))}</th>'
      '<th>${_esc(s.pick('Extracted', 'Đã trích ảnh'))}</th>'
      '<th>${_esc(s.pick('Image-reviewed', 'Đã chấm bằng ảnh'))}</th>'
      '<th>${_esc(s.pick('Text-only/skipped', 'Chỉ văn bản/bỏ qua'))}</th>'
      '<th>${_esc(s.pick('Image failures', 'Ảnh lỗi'))}</th></tr>'
      '<tr><td>${c.candidates}</td><td>${c.extracted}</td>'
      '<td>${c.reviewed}</td><td>${c.skipped}</td><td>${c.failed}</td></tr>'
      '</table></div>\n',
    );
  }

  // ── Verdict (rubric E, same compute as both other twins) ───────────────
  final verdict = computeVerdict([...syllabusFindings, ...referenceFindings]);
  out.write(
    '<h2>${_esc(s.pick('Verdict (rubric E, 10-point)', 'Kết luận (rubric E, thang 10 điểm)'))}</h2>',
  );
  out.write('<p class="meta"><strong>${_esc(verdict.display)}</strong></p>');
  out.write(
    '<div class="tscroll"><table>'
    '<tr><th>${_esc(s.pick('Component', 'Thành phần'))}</th>'
    '<th>${_esc(s.pick('State', 'Trạng thái'))}</th></tr>',
  );
  for (final entry in <String, String>{
    s.pick('Floor (7 SRS criteria, 5 pts)', 'Sàn (7 tiêu chí SRS, 5 điểm)'): s
        .componentState(verdict.floor),
    s.pick('Diagrams clean (2 pts)', 'Sơ đồ sạch (2 điểm)'): s.componentState(
      verdict.diagram,
    ),
    s.pick('Cross-artifact clean (2 pts)', 'Nhất quán xuyên tài liệu (2 điểm)'):
        s.componentState(verdict.crossArtifact),
    s.pick(
      'Traceability UC→design→test (1 pt)',
      'Truy vết UC→thiết kế→kiểm thử (1 điểm)',
    ): '${s.componentState(verdict.traceability)} '
        '${s.pick('(no test-artifact input in this tool)', '(công cụ này chưa có dữ liệu kiểm thử)')}',
    s.pick(
      'Deductions −1 per 🔴 ERD/SM/SEQ-CLS row',
      'Trừ −1 mỗi dòng 🔴 ERD/SM/SEQ-CLS',
    ): '${verdict.deductions}',
  }.entries) {
    out.write(
      '<tr><td>${_esc(entry.key)}</td><td>${_esc(entry.value)}</td></tr>',
    );
  }
  out.write('</table></div>\n');

  // ── Scores by section (same rollup as the markdown twin) ──────────────
  if (result != null && result.scores.isNotEmpty) {
    final sections = summarizeSections(units: units, result: result);
    if (sections.isNotEmpty) {
      out.write(
        '<h2>${_esc(s.pick('Scores by section', 'Điểm theo mục'))}</h2>'
        '<p class="meta">${_esc(s.pick('Worst average first — start fixing at the top. Bars are average score /10.', 'Điểm trung bình thấp nhất xếp trước — sửa từ trên xuống. Thanh là điểm trung bình trên 10.'))}</p>',
      );
      for (final section in sections) {
        final avg = section.averageScore;
        final pct = avg == null ? 0 : (avg.clamp(0, 10) * 10).round();
        final tone = avg == null
            ? 'grey'
            : avg < 4
            ? 'red'
            : avg < 7
            ? 'amber'
            : 'green';
        out.write(
          '<div class="bar"><div class="blabel">${_esc(section.section)} '
          '<span class="bsub">${_esc(s.pick('avg', 'TB'))} '
          '${avg == null ? '—' : avg.toStringAsFixed(1)}'
          ' · ${section.reviewedCount} ${_esc(s.pick('scored', 'đã chấm'))}'
          ' · ${section.findingCount} ${_esc(s.pick('to fix', 'cần sửa'))}'
          ' · ${section.highSeverityCount} ${_esc(s.pick('high', 'nghiêm trọng'))}'
          '</span></div>'
          '<div class="track"><div class="fill $tone" style="width:$pct%"></div></div></div>',
        );
      }
      out.write('\n');
    }
  }

  // ── Model findings, grouped by severity ───────────────────────────────
  if (findings.isEmpty) {
    final message = result == null
        ? s.pick(
            'No findings yet — run a review to populate this section.',
            'Chưa có lỗi nào — hãy chạy một lượt chấm để có dữ liệu cho mục này.',
          )
        : result.reviewed > 0
        ? s.pick(
            'The run reviewed ${result.reviewed} unit(s) and verified no issues worth reporting.',
            'Lượt chấm đã chấm ${result.reviewed} mục và không có lỗi nào đáng báo cáo.',
          )
        : s.pick(
            'No findings — no unit was successfully reviewed. See the warning above.',
            'Không có lỗi — không mục nào được chấm thành công. Xem cảnh báo ở trên.',
          );
    out.write(
      '<h2>${_esc(s.pick('Findings', 'Lỗi phát hiện'))}</h2>\n'
      '<p class="meta">${_esc(message)}</p>\n',
    );
  } else {
    final accepted = findings
        .where((f) => statusFor(f.id) == FindingStatus.fixed)
        .length;
    final dismissed = findings
        .where((f) => statusFor(f.id) == FindingStatus.disputed)
        .length;
    final triage = accepted > 0 || dismissed > 0
        ? ' <span class="triage">${_esc(s.pick('Triage: $accepted accepted · $dismissed dismissed · ${findings.length - accepted - dismissed} still open.', 'Phân loại: $accepted đã sửa · $dismissed phản hồi là sai · ${findings.length - accepted - dismissed} còn để ngỏ.'))}</span>'
        : '';
    out.write(
      '<h2>${_esc(s.pick('Findings', 'Lỗi phát hiện'))} '
      '(${findings.length})$triage</h2>\n',
    );
    for (final severity in const [
      Severity.high,
      Severity.medium,
      Severity.low,
    ]) {
      final group = findings
          .where((f) => f.severity == severity)
          .toList(growable: false);
      if (group.isEmpty) continue;
      final cls = switch (severity) {
        Severity.high => 'high',
        Severity.medium => 'medium',
        Severity.low => 'low',
      };
      out.write(
        '<h3 class="$cls">${_esc(s.severityLabel(severity))} '
        '(${group.length})</h3>\n',
      );
      for (final finding in group) {
        out.write(
          '<div class="finding $cls"><div class="fhead">'
          '<b>${_esc(finding.requirementId)} · ${_esc(finding.title)}</b>'
          '<span class="chips">'
          '<span class="chip">${_esc(s.findingStatusLabel(statusFor(finding.id)))}</span>'
          '<span class="chip">${_esc(s.pick('page', 'trang'))} ${finding.pageIndex + 1}</span>'
          '<span class="chip">${_esc(s.verificationLabel(finding.issue.verification))}</span>'
          // Which rubric row this finding answers — the one value that traces it
          // back to a criterion a user added or edited.
          '${finding.issue.criterionId == null || finding.issue.criterionId!.isEmpty ? '' : '<span class="chip">${_esc(s.criterionRef(finding.issue.criterionId!))}</span>'}'
          '</span></div>'
          '<blockquote>${_esc(finding.quote)}</blockquote>'
          '<p class="sugg"><b>${_esc(s.pick('Suggestion', 'Gợi ý'))}.</b> '
          '${_esc(finding.suggestion)}</p></div>\n',
        );
      }
    }
  }

  // ── Deterministic checks (syllabus + reference M2, family-labelled) ───
  // Grouped view first: 126 rows of "UC-xx has no Postcondition" is a
  // ledger, not a dashboard. A human should read "one check, 126 use
  // cases" in one line and expand only if they want the names. The full
  // per-row ledger stays below, collapsed — nothing is hidden, the
  // default reading order just stops punishing repetition.
  final allDeterministic = reportDeterministicRows(
    s: s,
    syllabusFindings: syllabusFindings,
    referenceFindings: referenceFindings,
    blueprintFindings: blueprintFindings,
  );
  if (allDeterministic.isNotEmpty) {
    final failing = allDeterministic.where((e) => !e.$2.passed).length;
    // The re-review tally — sds-reviewer's "grep -c OPEN" rendered for
    // humans. Only meaningful once a Verifier re-run has populated
    // statuses; a first export says plain "need attention" instead.
    final openCount = allDeterministic
        .where(
          (e) =>
              !e.$2.passed && statusFor(e.$2.ledgerKey) == FindingStatus.open,
        )
        .length;
    final fixedCount = allDeterministic
        .where(
          (e) =>
              !e.$2.passed && statusFor(e.$2.ledgerKey) == FindingStatus.fixed,
        )
        .length;
    final verifiedCount = allDeterministic
        .where(
          (e) =>
              !e.$2.passed &&
              (statusFor(e.$2.ledgerKey) == FindingStatus.verified ||
                  statusFor(e.$2.ledgerKey) == FindingStatus.disputed),
        )
        .length;
    final hasLedgerState = fixedCount + verifiedCount > 0;
    out.write(
      '<h2>${_esc(s.pick('Deterministic checks', 'Kiểm tra bằng luật'))} '
      '(${allDeterministic.length})</h2>'
      '<p class="meta">${_esc(s.pick('Offline rule checks — no model, zero tokens. syllabus rows come from the SEP490 rubric (F7/F8/F9) and the srs-writer quality scan; reference (M2) rows are the consistency checks (duplicate ids, missing postconditions, cross-artifact names).', 'Kiểm tra bằng luật ngoại tuyến — không gọi model, không tốn token. Nhóm syllabus đến từ thang SEP490 (F7/F8/F9) và bộ quét chất lượng của srs-writer; nhóm mùi nhất quán (M2) là các kiểm tra nhất quán (mã trùng, thiếu hậu điều kiện, tên thực thể khác nhau giữa các mục).'))} '
      '${failing == 0 ? _esc(s.pick('All checks passed.', 'Tất cả kiểm tra đều đạt.')) : _esc(s.pick('$failing of ${allDeterministic.length} need attention.', '$failing/${allDeterministic.length} mục cần xử lý.'))}'
      '${hasLedgerState ? ' ${_esc(s.pick('Ledger:', 'Sổ theo dõi:'))} <b>$openCount ${_esc(s.pick('open', 'đang mở'))}</b> · $fixedCount ${_esc(s.pick('fixed (awaiting re-verify)', 'đã sửa (chờ xác minh lại)'))} · $verifiedCount ${_esc(s.pick('verified/disputed', 'đã xác minh/phản hồi sai'))}.' : ''}</p>',
    );

    // Group key: same family, check, pass-state, severity, and message
    // SHAPE (the subject id swapped for a placeholder, so per-UC wording
    // variants of one defect collapse together while genuinely different
    // messages — thin vs oversized — stay apart).
    final groups = <_CheckGroup, List<String>>{};
    final order = <_CheckGroup>[];
    for (final (family, finding) in allDeterministic) {
      final detail = finding.messageFor(language);
      final template =
          finding.subject != null && detail.contains(finding.subject!)
          ? detail.replaceAll(finding.subject!, '⟨id⟩')
          : detail;
      final group = _CheckGroup(
        family: family,
        label: s.checkLabel(finding.check),
        passed: finding.passed,
        severity: finding.severity.name,
        template: template,
        vision: finding.requiresVisionEvidence,
      );
      if (!groups.containsKey(group)) {
        groups[group] = <String>[];
        order.add(group);
      }
      groups[group]!.add(
        finding.subject ?? s.pick('whole document', 'toàn tài liệu'),
      );
    }

    out.write(
      '<div class="tscroll"><table>'
      '<tr><th>${_esc(s.pick('Family', 'Nhóm'))}</th>'
      '<th>${_esc(s.pick('Check', 'Kiểm tra'))}</th>'
      '<th>${_esc(s.pick('Result', 'Kết quả'))}</th>'
      '<th>${_esc(s.pick('Count', 'Số lượng'))}</th>'
      '<th>${_esc(s.pick('Affected', 'Ảnh hưởng'))}</th>'
      '<th>${_esc(s.pick('Detail', 'Chi tiết'))}</th></tr>',
    );
    for (final group in order) {
      final subjects = groups[group]!;
      const inline = 6;
      final subjectCell = subjects.length <= inline
          ? subjects.map(_esc).join(', ')
          : '${subjects.take(inline).map(_esc).join(', ')} '
                '<details class="more"><summary>'
                '+${subjects.length - inline} ${_esc(s.pick('more', 'mục nữa'))}'
                '</summary>${subjects.map(_esc).join(', ')}</details>';
      final resultCell = group.passed
          ? '<td class="ok">${_esc(s.passedFailed(true))}</td>'
          : '<td class="bad">${_esc(_localizedSeverity(s, group.severity))}</td>';
      final visionChip = group.vision
          ? ' <span class="chip amber">${_esc(s.pick('needs vision evidence', 'cần bằng chứng hình ảnh'))}</span>'
          : '';
      out.write(
        '<tr><td>${_esc(group.family)}</td><td>${_esc(group.label)}</td>'
        '$resultCell<td><b>${subjects.length}</b></td>'
        '<td>$subjectCell</td><td>${_esc(group.template)}$visionChip</td></tr>',
      );
    }
    out.write('</table></div>\n');

    // Full ledger, collapsed — the JSON twin and the markdown carry it
    // row-by-row; this keeps the same artefact readable AND complete.
    out.write(
      '<details><summary>${_esc(s.pick('Full ledger', 'Sổ theo dõi đầy đủ'))} '
      '(${allDeterministic.length} ${_esc(s.pick('rows', 'dòng'))})</summary>'
      '<div class="tscroll"><table>'
      '<tr><th>${_esc(s.pick('Family', 'Nhóm'))}</th>'
      '<th>${_esc(s.pick('Check', 'Kiểm tra'))}</th>'
      '<th>${_esc(s.pick('Subject', 'Đối tượng'))}</th>'
      '<th>${_esc(s.pick('Result', 'Kết quả'))}</th>'
      '<th>${_esc(s.pick('Status', 'Trạng thái'))}</th>'
      '<th>${_esc(s.pick('Detail', 'Chi tiết'))}</th></tr>',
    );
    for (final (family, finding) in allDeterministic) {
      final resultCell = finding.passed
          ? '<td class="ok">${_esc(s.passedFailed(true))}</td>'
          : '<td class="bad">${_esc(s.severityLabel(finding.severity))}</td>';
      final status = finding.passed
          ? '<td>—</td>'
          : '<td><span class="chip ${_statusClass(statusFor(finding.ledgerKey))}">'
                '${_esc(s.findingStatusLabel(statusFor(finding.ledgerKey)))}'
                '</span></td>';
      final visionChip = finding.requiresVisionEvidence
          ? ' <span class="chip amber">${_esc(s.pick('needs vision evidence', 'cần bằng chứng hình ảnh'))}</span>'
          : '';
      out.write(
        '<tr><td>${_esc(family)}</td>'
        '<td>${_esc(s.checkLabel(finding.check))}</td>'
        '<td>${_esc(finding.subject ?? s.pick('whole document', 'toàn tài liệu'))}</td>'
        '$resultCell$status'
        '<td>${_esc(finding.messageFor(language))}$visionChip</td></tr>',
      );
    }
    out.write('</table></div></details>\n');
  }
  // -- Human-reported issues (reviewer-entered, not model output) --
  if (humanIssues.isNotEmpty) {
    out.write(
      '<h2>${_esc(s.pick('Human-reported issues', 'Lỗi do người review ghi'))} '
      '(${humanIssues.length})</h2>',
    );
    out.write(
      '<p class="meta">${_esc(s.pick('Entered by a reviewer in the app — not model output.', 'Do người review nhập trong ứng dụng — không phải kết quả của model.'))}</p><ul>',
    );
    for (final issue in humanIssues) {
      final stamp = issue.createdAt.toUtc().toIso8601String();
      out.write('<li><b>${_esc(issue.title)}</b>');
      out.write(
        '<span class="chip">${_esc(s.severityLabel(issue.severity))}</span>',
      );
      out.write(
        '<span class="meta">${_esc(issue.section ?? '')} '
        '${_esc(stamp)}</span>',
      );
      if (issue.detail.isNotEmpty) {
        out.write('<br>${_esc(issue.detail)}');
      }
      out.write('</li>');
    }
    out.write('</ul>');
  }

  // ── Inventory (collapsed: it is long) ─────────────────────────────────
  out.write(
    '<details><summary>${_esc(s.pick('Inventory', 'Danh mục tài liệu'))} '
    '(${units.length} ${_esc(s.pick('units', 'mục'))})</summary>'
    '<div class="tscroll"><table>'
    '<tr><th>${_esc(s.pick('ID', 'Mã'))}</th>'
    '<th>${_esc(s.pick('Requirement', 'Yêu cầu'))}</th>'
    '<th>${_esc(s.pick('Kind', 'Loại'))}</th>'
    '<th>${_esc(s.pick('Page', 'Trang'))}</th>'
    '<th>${_esc(s.pick('Status', 'Trạng thái'))}</th></tr>',
  );
  for (final unit in units) {
    out.write(
      '<tr><td>${_esc(unit.id)}</td><td>${_esc(unit.title)}</td>'
      '<td>${_esc(s.unitKindLabel(unit.kind))}</td>'
      '<td>${unit.pageIndex + 1}</td>'
      '<td>${_esc(s.unitStatusLabel(unit.status.name))}'
      '${unit.malformed ? ' · ${_esc(s.pick('MALFORMED', 'LỖI ĐỊNH DẠNG'))}' : ''}</td></tr>',
    );
  }
  out.write('</table></div></details>\n');

  // ── Limitations (shared source with both twins) ───────────────────────
  out.write(
    '<h2>${_esc(s.pick('Limitations & future work', 'Giới hạn & hướng tiếp theo'))}</h2><ul>',
  );
  for (final limitation in reportLimitations(
    offline: reportOffline,
    language: language,
  )) {
    out.write('<li>${_esc(limitation)}</li>');
  }
  out.write(
    '</ul>\n<footer>${_esc(s.pick('Generated by SRS Review AI · schema srs-review/report · self-contained document, no external resources', 'Do SRS Review AI tạo · schema srs-review/report · tài liệu tự chứa, không dùng tài nguyên bên ngoài'))}</footer>\n'
    '</body>\n</html>',
  );
  return out.toString();
}

const String _css = '''
:root { color-scheme: light; }
* { box-sizing: border-box; }
body { font: 15px/1.55 -apple-system, "Segoe UI", Roboto, "Helvetica Neue",
  Arial, sans-serif; margin: 0; padding: 32px 20px; color: #1f2937;
  background: #f8fafc; max-width: 880px; margin-inline: auto; }
header h1 { margin: 0 0 4px; font-size: 26px; }
.meta { color: #64748b; font-size: 13px; margin: 4px 0; }
h2 { font-size: 19px; margin: 28px 0 10px; border-bottom: 2px solid #e2e8f0;
  padding-bottom: 4px; }
h3 { font-size: 15px; margin: 18px 0 8px; }
h3.high { color: #b91c1c; } h3.medium { color: #b45309; }
h3.low { color: #15803d; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px,
  1fr)); gap: 10px; }
.card { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
  padding: 12px; text-align: center; }
.card .num { font-size: 26px; font-weight: 700; }
.num.red { color: #b91c1c; } .num.amber { color: #b45309; }
.card .lbl { font-size: 12px; color: #64748b; }
.banner { border-radius: 10px; padding: 10px 14px; margin: 10px 0;
  font-size: 14px; border: 1px solid; }
.banner.red { background: #fef2f2; border-color: #fecaca; color: #7f1d1d; }
.banner.amber { background: #fffbeb; border-color: #fde68a; color: #78350f; }
.banner.grey { background: #f1f5f9; border-color: #e2e8f0; color: #334155; }
.chip { display: inline-block; font-size: 11px; border-radius: 999px;
  padding: 2px 9px; border: 1px solid #cbd5e1; background: #fff;
  color: #475569; margin-left: 6px; }
.chip.amber { background: #fef3c7; border-color: #fcd34d; color: #92400e; }
.chip.blue { background: #dbeafe; border-color: #93c5fd; color: #1e40af; }
table { border-collapse: collapse; width: 100%; background: #fff;
  font-size: 13px; }
/* Wide ledgers scroll inside their own box; the page never gains a
   horizontal scrollbar (measured: the 5-column check table needs ~423px
   at 390px viewport). */
.tscroll { overflow-x: auto; -webkit-overflow-scrolling: touch; }
th, td { border: 1px solid #e2e8f0; padding: 6px 9px; text-align: left;
  vertical-align: top; }
th { background: #f1f5f9; }
td.ok { color: #15803d; font-weight: 600; }
td.bad { color: #b91c1c; font-weight: 700; }
.bar { margin: 8px 0; }
.blabel { font-size: 13px; font-weight: 600; }
.bsub { font-weight: 400; color: #64748b; font-size: 12px; }
.track { background: #e2e8f0; border-radius: 6px; height: 10px;
  margin-top: 3px; overflow: hidden; }
.fill { height: 100%; border-radius: 6px; }
.fill.red { background: #dc2626; } .fill.amber { background: #d97706; }
.fill.green { background: #16a34a; } .fill.grey { background: #94a3b8; }
.finding { background: #fff; border: 1px solid #e2e8f0; border-left-width: 4px;
  border-radius: 10px; padding: 10px 14px; margin: 10px 0; }
.finding.high { border-left-color: #dc2626; }
.finding.medium { border-left-color: #d97706; }
.finding.low { border-left-color: #16a34a; }
.fhead { display: flex; justify-content: space-between; gap: 10px;
  flex-wrap: wrap; }
blockquote { margin: 8px 0; padding: 6px 12px; border-left: 3px solid #cbd5e1;
  background: #f8fafc; color: #334155; white-space: pre-wrap; }
.sugg { font-size: 14px; margin: 6px 0 0; }
.triage { font-weight: 400; font-size: 13px; color: #64748b; }
details { margin: 14px 0; } summary { cursor: pointer; font-weight: 600; }
details.more { display: inline; margin: 0; font-weight: 400; }
details.more summary { display: inline; color: #1d4ed8; font-weight: 400; }
footer { margin-top: 34px; color: #94a3b8; font-size: 12px; }
''';
