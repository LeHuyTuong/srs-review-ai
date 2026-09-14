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
import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import 'report_export.dart';
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
  int diagramPageCount = 0,
  bool imageReviewAvailable = false,
  int imageReviewedCount = 0,
  PageImageCoverage? imageCoverage,
  Map<String, FindingStatus> findingStatus = const {},
}) {
  // Same effective-mode rule as both twins: the run's own mock flag outranks
  // the toggle at export time.
  final reportOffline = result?.mock ?? offline;
  final findings = result?.findings ?? const <FindingRow>[];
  final skipped = result?.skipped ?? units.where((u) => !u.selected).length;
  FindingStatus statusFor(String id) =>
      findingStatus[id] ?? FindingStatus.open;
  final now = DateTime.now().toUtc();
  final generated = now.toIso8601String();
  final effectiveImageReviewedCount =
      imageCoverage?.reviewed ?? imageReviewedCount;
  final imageReviewUsed =
      imageReviewAvailable && !reportOffline && effectiveImageReviewedCount > 0;
  final imageReviewCapable = imageReviewAvailable && !reportOffline;

  final out = StringBuffer()
    ..write('<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">')
    ..write(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    )
    ..write('<title>SRS Review — ${_esc(fileName)}</title>')
    ..write('<style>$_css</style>\n</head>\n<body>\n');

  // ── Header ────────────────────────────────────────────────────────────
  final modeChip = reportOffline
      ? '<span class="chip amber">Offline mock — not a live AI assessment</span>'
      : '<span class="chip blue">Online proxy — not official grading</span>';
  out.write(
    '<header><h1>SRS Review Report</h1>'
    '<p class="meta">${_esc(fileName)} · ${_esc(result?.rubricVersion ?? kRubricLabel)}'
    ' · generated ${_esc(generated)}</p><p>$modeChip</p></header>\n',
  );

  // ── Coverage cards ────────────────────────────────────────────────────
  out.write('<h2>Coverage</h2>\n<div class="cards">');
  void card(String label, String value, [String tone = '']) {
    out.write(
      '<div class="card"><div class="num $tone">$value</div>'
      '<div class="lbl">$label</div></div>',
    );
  }

  card('Reviewed', '${result?.reviewed ?? 0}');
  card('Failed', '${result?.failed ?? 0}', (result?.failed ?? 0) > 0 ? 'red' : '');
  card('Skipped', '$skipped');
  card('Total units', '${units.length}');
  card(
    'Unverified dropped',
    '${result?.droppedIssueCount ?? 0}',
    (result?.droppedIssueCount ?? 0) > 0 ? 'amber' : '',
  );
  out.write('</div>\n');

  // ── Honesty banners (same conditions as the markdown's notes) ─────────
  if (result != null &&
      (result.outcome != 'done' || result.reviewed == 0 || result.failed > 0)) {
    final ended = switch (result.outcome) {
      'cancelled' => 'was cancelled',
      'failed' => 'failed — quota, provider or proxy error',
      _ => 'completed',
    };
    final failedNote = result.failed > 0
        ? ' ${result.failed} selected unit(s) errored and were NOT reviewed.'
        : '';
    out.write(
      '<div class="banner red"><b>The last review run $ended — only '
      '${result.reviewed} selected unit(s) returned results.$failedNote</b> '
      'Units are marked reviewed only where the run returned a result; the '
      'rest are pending or failed, and nothing was assessed for them.</div>\n',
    );
  }
  final showImageReviewNote =
      diagramPageCount > 0 ||
      imageReviewAvailable ||
      imageReviewedCount > 0 ||
      imageCoverage != null;
  if (showImageReviewNote) {
    final note = reportOffline
        ? '<b>Offline mock mode performed a text-only review.</b> PDF page '
              'images were not sent to the model; any diagram content was '
              'assessed from extracted text. Treat "no issues found" as '
              '"nothing the text gave away".'
        : imageReviewUsed
        ? '<b>PDF image review was available, and $effectiveImageReviewedCount '
              'requirement(s) were reviewed with page images.</b> Other '
              'requirements were assessed from extracted text alone.'
        : imageReviewCapable
        ? '<b>PDF page images were available, but none were attached to a '
              'successful review request.</b> Any diagram content was '
              'therefore text-only.'
        : '<b>PDF page images were NOT available for this document or '
              'session.</b> Any diagram content was text-only; review '
              'findings came from extracted text.';
    out.write('<div class="banner grey">🖼️ $note</div>\n');
    if (diagramPageCount > 0) {
      out.write(
        '<p class="meta">Diagram-like pages detected: $diagramPageCount</p>\n',
      );
    }
  }
  if (imageCoverage != null) {
    final c = imageCoverage;
    out.write(
      '<h3>PDF page-image coverage</h3>'
      '<div class="tscroll"><table><tr><th>Candidates</th><th>Extracted</th><th>Image-reviewed</th>'
      '<th>Text-only/skipped</th><th>Image failures</th></tr>'
      '<tr><td>${c.candidates}</td><td>${c.extracted}</td>'
      '<td>${c.reviewed}</td><td>${c.skipped}</td><td>${c.failed}</td></tr></table></div>\n',
    );
  }

  // ── Scores by section (same rollup as the markdown twin) ──────────────
  if (result != null && result.scores.isNotEmpty) {
    final sections = summarizeSections(units: units, result: result);
    if (sections.isNotEmpty) {
      out.write(
        '<h2>Scores by section</h2>'
        '<p class="meta">Worst average first — start fixing at the top. '
        'Bars are average score /10.</p>',
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
          '<span class="bsub">avg ${avg == null ? '—' : avg.toStringAsFixed(1)}'
          ' · ${section.reviewedCount} scored · ${section.findingCount} to fix'
          ' · ${section.highSeverityCount} high</span></div>'
          '<div class="track"><div class="fill $tone" style="width:$pct%"></div></div></div>',
        );
      }
      out.write('\n');
    }
  }

  // ── Model findings, grouped by severity ───────────────────────────────
  if (findings.isEmpty) {
    final message = result == null
        ? 'No findings yet — run a review to populate this section.'
        : result.reviewed > 0
        ? 'The run reviewed ${result.reviewed} unit(s) and verified no '
              'issues worth reporting.'
        : 'No findings — no unit was successfully reviewed. See the warning '
              'above.';
    out.write('<h2>Findings</h2>\n<p class="meta">${_esc(message)}</p>\n');
  } else {
    final accepted = findings
        .where((f) => statusFor(f.id) == FindingStatus.fixed)
        .length;
    final dismissed = findings
        .where((f) => statusFor(f.id) == FindingStatus.disputed)
        .length;
    final triage = accepted > 0 || dismissed > 0
        ? ' <span class="triage">Triage: $accepted accepted · $dismissed '
              'dismissed · ${findings.length - accepted - dismissed} still open.</span>'
        : '';
    out.write('<h2>Findings (${findings.length})$triage</h2>\n');
    for (final severity in const [Severity.high, Severity.medium, Severity.low]) {
      final group = findings
          .where((f) => f.severity == severity)
          .toList(growable: false);
      if (group.isEmpty) continue;
      final cls = switch (severity) {
        Severity.high => 'high',
        Severity.medium => 'medium',
        Severity.low => 'low',
      };
      out.write('<h3 class="$cls">${severity.name} (${group.length})</h3>\n');
      for (final finding in group) {
        out.write(
          '<div class="finding $cls"><div class="fhead">'
          '<b>${_esc(finding.requirementId)} · ${_esc(finding.title)}</b>'
          '<span class="chips">'
          '<span class="chip">${_esc(statusFor(finding.id).label)}</span>'
          '<span class="chip">page ${finding.pageIndex + 1}</span>'
          '<span class="chip">${_esc(finding.issue.verification.name)} match</span>'
          '</span></div>'
          '<blockquote>${_esc(finding.quote)}</blockquote>'
          '<p class="sugg"><b>Suggestion.</b> ${_esc(finding.suggestion)}</p></div>\n',
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
  final allDeterministic = [
    for (final f in syllabusFindings) ('syllabus', f),
    for (final f in referenceFindings) ('reference (M2)', f),
  ];
  if (allDeterministic.isNotEmpty) {
    final failing = allDeterministic.where((e) => !e.$2.passed).length;
    // The re-review tally — sds-reviewer's "grep -c OPEN" rendered for
    // humans. Only meaningful once a Verifier re-run has populated
    // statuses; a first export says plain "need attention" instead.
    final openCount = allDeterministic
        .where((e) =>
            !e.$2.passed && statusFor(e.$2.ledgerKey) == FindingStatus.open)
        .length;
    final fixedCount = allDeterministic
        .where((e) => !e.$2.passed &&
            statusFor(e.$2.ledgerKey) == FindingStatus.fixed)
        .length;
    final verifiedCount = allDeterministic
        .where((e) => !e.$2.passed &&
            (statusFor(e.$2.ledgerKey) == FindingStatus.verified ||
                statusFor(e.$2.ledgerKey) == FindingStatus.disputed))
        .length;
    final hasLedgerState = fixedCount + verifiedCount > 0;
    out.write(
      '<h2>Deterministic checks (${allDeterministic.length})</h2>'
      '<p class="meta">Offline rule checks — no model, zero tokens. '
      'syllabus rows come from the SEP490 rubric (F7/F8/F9) and the '
      'srs-writer quality scan; reference (M2) '
      'rows are the consistency checks (duplicate ids, missing '
      'postconditions, cross-artifact names). '
      '${failing == 0 ? 'All checks passed.' : '<b>$failing of ${allDeterministic.length} need attention.</b>'}'
      '${hasLedgerState ? ' Ledger: <b>$openCount open</b> · $fixedCount fixed (awaiting re-verify) · $verifiedCount verified/disputed.' : ''}</p>',
    );

    // Group key: same family, check, pass-state, severity, and message
    // SHAPE (the subject id swapped for a placeholder, so per-UC wording
    // variants of one defect collapse together while genuinely different
    // messages — thin vs oversized — stay apart).
    final groups = <_CheckGroup, List<String>>{};
    final order = <_CheckGroup>[];
    for (final (family, finding) in allDeterministic) {
      final template = finding.subject != null &&
              finding.message.contains(finding.subject!)
          ? finding.message.replaceAll(finding.subject!, '⟨id⟩')
          : finding.message;
      final group = _CheckGroup(
        family: family,
        label: finding.check.label,
        passed: finding.passed,
        severity: finding.severity.name,
        template: template,
        vision: finding.requiresVisionEvidence,
      );
      if (!groups.containsKey(group)) {
        groups[group] = <String>[];
        order.add(group);
      }
      groups[group]!.add(finding.subject ?? 'whole document');
    }

    out.write(
      '<div class="tscroll"><table><tr><th>Family</th><th>Check</th>'
      '<th>Result</th><th>Count</th><th>Affected</th><th>Detail</th></tr>',
    );
    for (final group in order) {
      final subjects = groups[group]!;
      const inline = 6;
      final subjectCell = subjects.length <= inline
          ? subjects.map(_esc).join(', ')
          : '${subjects.take(inline).map(_esc).join(', ')} '
                '<details class="more"><summary>+${subjects.length - inline} '
                'more</summary>${subjects.map(_esc).join(', ')}</details>';
      final resultCell = group.passed
          ? '<td class="ok">passed</td>'
          : '<td class="bad">${_esc(group.severity)}</td>';
      out.write(
        '<tr><td>${_esc(group.family)}</td><td>${_esc(group.label)}</td>'
        '$resultCell<td><b>${subjects.length}</b></td>'
        '<td>$subjectCell</td><td>${_esc(group.template)}'
        '${group.vision ? ' <span class="chip amber">needs vision evidence</span>' : ''}</td></tr>',
      );
    }
    out.write('</table></div>\n');

    // Full ledger, collapsed — the JSON twin and the markdown carry it
    // row-by-row; this keeps the same artefact readable AND complete.
    out.write(
      '<details><summary>Full ledger (${allDeterministic.length} rows)</summary>'
      '<div class="tscroll"><table><tr><th>Family</th><th>Check</th>'
      '<th>Subject</th><th>Result</th><th>Status</th><th>Detail</th></tr>',
    );
    for (final (family, finding) in allDeterministic) {
      final resultCell = finding.passed
          ? '<td class="ok">passed</td>'
          : '<td class="bad">${_esc(finding.severity.name)}</td>';
      final status = finding.passed
          ? '<td>—</td>'
          : '<td><span class="chip ${_statusClass(statusFor(finding.ledgerKey))}">'
              '${_esc(statusFor(finding.ledgerKey).label)}</span></td>';
      out.write(
        '<tr><td>${_esc(family)}</td><td>${_esc(finding.check.label)}</td>'
        '<td>${_esc(finding.subject ?? 'whole document')}</td>$resultCell$status'
        '<td>${_esc(finding.message)}'
        '${finding.requiresVisionEvidence ? ' <span class="chip amber">needs vision evidence</span>' : ''}</td></tr>',
      );
    }
    out.write('</table></div></details>\n');
  }

  // ── Inventory (collapsed: it is long) ─────────────────────────────────
  out.write(
    '<details><summary>Inventory (${units.length} units)</summary>'
    '<div class="tscroll"><table><tr><th>ID</th><th>Requirement</th><th>Kind</th><th>Page</th>'
    '<th>Status</th></tr>',
  );
  for (final unit in units) {
    out.write(
      '<tr><td>${_esc(unit.id)}</td><td>${_esc(unit.title)}</td>'
      '<td>${_esc(unit.kind.label)}</td><td>${unit.pageIndex + 1}</td>'
      '<td>${_esc(unit.status.name)}${unit.malformed ? ' · MALFORMED' : ''}</td></tr>',
    );
  }
  out.write('</table></div></details>\n');

  // ── Limitations (shared source with both twins) ───────────────────────
  out.write(
    '<h2>Limitations &amp; future work</h2><ul>',
  );
  for (final limitation in reportLimitations(offline: reportOffline)) {
    out.write('<li>${_esc(limitation)}</li>');
  }
  out.write('</ul>\n<footer>Generated by SRS Review AI · schema '
      'srs-review/report · self-contained document, no external resources</footer>\n'
      '</body>\n</html>');
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
