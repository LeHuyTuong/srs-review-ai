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

import '../../../data/models/review_models.dart';
import 'workspace_findings.dart';
import 'workspace_unit.dart';

const String kRubricLabel = 'SEP490 · provisional v0.1';

String buildMarkdownReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,
}) {
  final skipped =
      result?.skipped ?? units.where((u) => !u.selected).length;
  final findings = result?.findings ?? const <FindingRow>[];
  final dropped = result?.droppedIssueCount ?? 0;

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
    '| **Mode** | ${offline ? 'Offline mock — not a live AI assessment' : 'Saved workspace — not a live AI assessment'} |',
    '',
    '## Coverage',
    '',
    '| Reviewed | Skipped | Failed | Total units | Unverified dropped |',
    '|---:|---:|---:|---:|---:|',
    '| ${result?.reviewed ?? 0} | $skipped | ${result?.failed ?? 0} | '
        '${units.length} | $dropped |',
    '',
  ];

  if (findings.isEmpty) {
    lines
      ..add('## Findings')
      ..add('')
      ..add('*No findings yet — run a review to populate this section.*')
      ..add('');
  } else {
    lines.add('## Findings (${findings.length})');
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
          ..add('`page ${finding.pageIndex + 1}` · '
              '`${finding.issue.verification.name} match`')
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
    final status = unit.malformed ? '${unit.status.name} · MALFORMED' : unit.status.name;
    lines.add(
      '| ${unit.id} | ${unit.title.replaceAll('|', '\\|')} | '
      '${unit.kind.label} | ${unit.pageIndex + 1} | $status |',
    );
  }

  lines
    ..add('')
    ..add('## Limitations & future work')
    ..add('')
    ..addAll(const [
      '- This is a mock review, not official grading; syllabus thresholds are '
          'provisional.',
      '- No OCR, live Gemini, resume/checkpoint, vision or precision/recall '
          'evaluation.',
      '- DOCX page references are logical extraction pages, not rendered '
          'pagination.',
      '- Imported documents are parsed locally; only explicitly saved sessions '
          'leave this device.',
      '- Demo content is synthetic, not measured OTES evidence.',
    ]);
  return lines.join('\n');
}

/// Severity ordering helper kept next to its only consumer.
int severityWeight(Severity severity) => severity.weight;
