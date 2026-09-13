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

import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import 'section_scores.dart';
import 'workspace_findings.dart';
import 'workspace_unit.dart';

const String kRubricLabel = 'SEP490 · provisional v0.1';

String buildMarkdownReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,

  /// F7/F8/F9 (and friends). These used to live only on the Syllabus tab and
  /// never reached an exported report, so half of what the app could prove for
  /// free was missing from the one artefact a supervisor actually reads.
  List<DeterministicFinding> syllabusFindings = const [],

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
  /// run. This is transient report context and is never persisted with the
  /// snapshot or saved session.
  PageImageCoverage? imageCoverage,

  /// Per-finding triage, keyed by finding id.
  Map<String, FindingStatus> findingStatus = const {},
}) {
  final skipped = result?.skipped ?? units.where((u) => !u.selected).length;
  final findings = result?.findings ?? const <FindingRow>[];
  final dropped = result?.droppedIssueCount ?? 0;
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

  final bySeverity = <Severity, List<FindingRow>>{};
  for (final finding in findings) {
    bySeverity.putIfAbsent(finding.severity, () => []).add(finding);
  }
  const severityGlyph = {
    Severity.high: '🔴 High',
    Severity.medium: '🟡 Medium',
    Severity.low: '🟢 Low',
  };
  const severityOrder = [Severity.high, Severity.medium, Severity.low];

  final lines = <String>[
    '# SRS Review Report',
    '',
    '| | |',
    '|---|---|',
    '| **Document** | $fileName |',
    '| **Generated** | $generated |',
    '| **Rubric** | ${result?.rubricVersion ?? kRubricLabel} |',
    '| **Mode** | ${reportOffline ? 'Offline mock — not a live AI assessment' : 'Online proxy — not official grading'} |',
    '',
    '## Coverage',
    '',
    '| Reviewed | Skipped | Failed | Total units | Unverified dropped |',
    '|---:|---:|---:|---:|---:|',
    '| ${result?.reviewed ?? 0} | $skipped | ${result?.failed ?? 0} | '
        '${units.length} | $dropped |',
    '',
  ];

  // The supervisor-facing answer to "which part scores what": the same
  // worst-first rollup the Findings tab shows. Sessions written before
  // scores existed simply have none, and the section is left out rather
  // than printed empty.
  if (result != null && result.scores.isNotEmpty) {
    final sections = summarizeSections(units: units, result: result);
    if (sections.isNotEmpty) {
      lines.addAll([
        '## Scores by section',
        '',
        'Worst average first — start fixing at the top.',
        '',
        '| Section | Avg /10 | Scored units | To fix | High |',
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
        ? '> 🖼️ **Offline mock mode performed a text-only review.** PDF page '
              'images were not sent to the model; any diagram content was assessed '
              'from extracted text. Treat "no issues found" as "nothing the text '
              'gave away".'
        : imageReviewUsed
        ? '> 🖼️ **PDF image review was available, and '
              '$effectiveImageReviewedCount requirement(s) were reviewed with page '
              'images.** Other requirements were assessed from extracted text '
              'alone; diagram content without an attached image was text-only. '
              'Treat "no issues found" for those requirements as "nothing the '
              'text gave away".'
        : imageReviewCapable
        ? '> 🖼️ **PDF page images were available, but none were '
              'attached to a successful review request.** Any diagram '
              'content was therefore text-only; treat "no issues found" as '
              '"nothing the text gave away".'
        : '> 🖼️ **PDF page images were NOT available for this document '
              'or session.** Any diagram content was text-only; review '
              'findings came from extracted text. Treat "no issues found" '
              'as "nothing the text gave away".';
    lines
      ..add(imageReviewNote)
      ..add('');
  }

  if (imageCoverage != null) {
    final coverage = imageCoverage;
    lines
      ..add('## PDF page-image coverage')
      ..add('')
      ..add(
        '| Candidates | Extracted | Image-reviewed | Text-only/skipped | Image failures |',
      )
      ..add('|---:|---:|---:|---:|---:|')
      ..add(
        '| ${coverage.candidates} | ${coverage.extracted} | '
        '${coverage.reviewed} | ${coverage.skipped} | ${coverage.failed} |',
      )
      ..add('')
      ..add(
        '`Text-only/skipped` includes ordinary text-only requirements and '
        'requirements whose image path was deferred or failed; `Image failures` '
        'counts image preparation or image-bearing request failures, not ordinary '
        'text-only requirements.',
      )
      ..add('');

    final reasonEntries = coverage.reasons.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (reasonEntries.isEmpty) {
      lines.add('Image-review reasons: none');
    } else {
      final reasonTokens = reasonEntries
          .map((entry) => 'reason=${entry.key}=${entry.value}')
          .join(', ');
      lines.add('Image-review reasons: $reasonTokens');
    }
    lines.add('');

    final decisionEntries = coverage.decisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (decisionEntries.isEmpty) {
      lines.add('Image-review decisions: none');
    } else {
      final decisionTokens = decisionEntries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      lines.add('Image-review decisions: $decisionTokens');
    }
    lines.add('');
  }

  // A run that never finished (cancelled, killed by quota/auth) or returned
  // nothing must say so in plain words. Coverage numbers alone, printed next
  // to a full inventory, read as "everything was reviewed" — the exact
  // confusion this report exists to prevent.
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
    lines
      ..add(
        '> ⚠️ **The last review run $ended — only ${result.reviewed} '
        'selected unit(s) returned results.$failedNote** Units are marked '
        '`reviewed` only where the run returned a result; the rest are '
        '`pending` or `failed`, and nothing was assessed for them.',
      )
      ..add('');
  }

  if (syllabusFindings.isNotEmpty) {
    final failing = syllabusFindings
        .where((finding) => !finding.passed)
        .toList(growable: false);
    lines
      ..add('## Deterministic checks (${syllabusFindings.length})')
      ..add('')
      ..add(
        'Offline rule checks taken from the SEP490 syllabus — no model, zero '
        'tokens, run the moment the document is imported. '
        '${failing.isEmpty ? 'All checks passed.' : '${failing.length} of ${syllabusFindings.length} need attention.'}',
      )
      ..add('')
      ..add('| Check | Subject | Result | Detail |')
      ..add('|---|---|---|---|');
    for (final finding in syllabusFindings) {
      lines.add(
        '| ${finding.check.label} | ${finding.subject ?? 'whole document'} | '
        '${finding.passed ? 'passed' : '**${finding.severity.name}**'} | '
        '${finding.message.replaceAll('|', '\\|')} |',
      );
    }
    lines.add('');
  }

  if (findings.isEmpty) {
    // Three different truths hide behind "no findings": nothing has run yet,
    // a run finished and verified nothing worth reporting, or a run returned
    // nothing at all. Each owes the reader a different sentence.
    final message = result == null
        ? '*No findings yet — run a review to populate this section.*'
        : result.reviewed > 0
        ? '*The run reviewed ${result.reviewed} unit(s) and verified no '
              'issues worth reporting.*'
        : '*No findings — no unit was successfully reviewed. See the '
              'warning above.*';
    lines
      ..add('## Findings')
      ..add('')
      ..add(message)
      ..add('');
  } else {
    FindingStatus statusFor(String id) =>
        findingStatus[id] ?? FindingStatus.open;
    final accepted = findings
        .where((finding) => statusFor(finding.id) == FindingStatus.accepted)
        .length;
    final dismissed = findings
        .where((finding) => statusFor(finding.id) == FindingStatus.dismissed)
        .length;

    lines.add('## Findings (${findings.length})');
    if (accepted > 0 || dismissed > 0) {
      lines
        ..add('')
        ..add(
          'Triage: $accepted accepted · $dismissed dismissed · '
          '${findings.length - accepted - dismissed} still open.',
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
            '`page ${finding.pageIndex + 1}` · '
            '`${finding.issue.verification.name} match` · '
            '`${statusFor(finding.id).label}`',
          )
          ..add('')
          ..addAll(finding.quote.split('\n').map((line) => '> $line'))
          ..add('')
          ..add('**Suggestion.** ${finding.suggestion}');
      }
    }
    lines.add('');
  }

  lines
    ..add('## Inventory (${units.length})')
    ..add('')
    ..add('| ID | Requirement | Kind | Page | Status |')
    ..add('|---|---|---|---|---|');
  for (final unit in units) {
    final status = unit.malformed
        ? '${unit.status.name} · MALFORMED'
        : unit.status.name;
    lines.add(
      '| ${unit.id} | ${unit.title.replaceAll('|', '\\|')} | '
      '${unit.kind.label} | ${unit.pageIndex + 1} | $status |',
    );
  }

  final limitations = <String>[
    reportOffline
        ? '- This is a mock review, not official grading; syllabus thresholds '
              'are provisional.'
        : '- Online proxy review is not official grading; syllabus thresholds '
              'are provisional.',
    '- No OCR. PDF page images are sent only for eligible pages in a newly '
        'imported PDF during an online run; DOCX, demo, and restored sessions '
        'are text-only. Requirements without an attached image are assessed '
        'from extracted text.',
    '- Page-image review is limited to detector-selected PDF pages and does '
        'not imply full visual understanding.',
    '- No resume/checkpoint, and no precision/recall evaluation against a '
        'labelled gold set.',
    '- DOCX page references are logical extraction pages, not rendered '
        'pagination.',
    reportOffline
        ? '- Offline mock review sends no model requests; source bytes are '
              'never saved in snapshots or sessions.'
        : '- Online PDF reviews may send bounded page images plus requirement '
              'text to the proxy; source bytes are never saved in snapshots or '
              'sessions. DOCX, demo, and restored sessions are text-only.',
    '- Demo content is synthetic, not measured OTES evidence.',
  ];
  lines
    ..add('')
    ..add('## Limitations & future work')
    ..add('')
    ..addAll(limitations);
  return lines.join('\n');
}

/// Severity ordering helper kept next to its only consumer.
int severityWeight(Severity severity) => severity.weight;
