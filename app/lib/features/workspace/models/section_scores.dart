/// Per-section rollup of one review run: how many points each part of the
/// document scored and which part needs the most work.
///
/// Pure data — no widgets, no Riverpod. The Findings tab renders it; the unit
/// tests assert it. Joining scores to sections needs the live inventory (the
/// result alone does not store a unit's section), which is why the entry
/// point takes both.
library;

import '../../../data/models/review_models.dart' show Severity;
import 'workspace_findings.dart';
import 'workspace_unit.dart';

/// One reviewed unit inside a [SectionScore], ready to render as a tappable
/// row: id, short title and the score the model gave it.
class UnitScore {
  const UnitScore({
    required this.key,
    required this.id,
    required this.title,
    required this.score,
    required this.findingCount,
  });

  final String key;
  final String id;
  final String title;
  final int score;
  final int findingCount;
}

/// Aggregate of one document section.
class SectionScore {
  const SectionScore({
    required this.section,
    required this.reviewedCount,
    required this.averageScore,
    required this.findingCount,
    required this.highSeverityCount,
    required this.units,
  });

  /// Heading shown in the UI. Units without a parsed heading land under
  /// [unclassifiedLabel] rather than vanishing.
  final String section;

  /// Units in this section that a run actually scored.
  final int reviewedCount;

  /// Mean of those scores, or null when the section has none yet — "not
  /// reviewed" and "reviewed and bad" must never render as the same number.
  final double? averageScore;

  final int findingCount;
  final int highSeverityCount;

  /// Scored units of this section, worst score first.
  final List<UnitScore> units;

  static const String unclassifiedLabel = 'Unclassified';
}

/// Rolls a run's per-unit scores up to its document sections.
///
/// Sections sort worst average first, so the top of the list answers "which
/// part do I fix now?" without the user reading every row. Unscored sections
/// keep their place at the bottom ordered by finding count, because findings
/// can exist for units from an earlier restored run whose scores were never
/// stored — they are still evidence that the section needs a pass.
List<SectionScore> summarizeSections({
  required List<WorkspaceUnit> units,
  required WorkspaceReviewResult? result,
}) {
  if (result == null || units.isEmpty) return const [];

  final findingsByUnit = <String, int>{};
  final highByUnit = <String, int>{};
  for (final finding in result.findings) {
    findingsByUnit[finding.unitKey] =
        (findingsByUnit[finding.unitKey] ?? 0) + 1;
    if (finding.severity == Severity.high) {
      highByUnit[finding.unitKey] = (highByUnit[finding.unitKey] ?? 0) + 1;
    }
  }

  final grouped = <String, List<WorkspaceUnit>>{};
  for (final unit in units) {
    final name = unit.section ?? SectionScore.unclassifiedLabel;
    grouped.putIfAbsent(name, () => []).add(unit);
  }

  final scores = <SectionScore>[];
  grouped.forEach((name, sectionUnits) {
    final scored = <UnitScore>[];
    var findings = 0;
    var high = 0;
    var reviewedHere = 0;
    for (final unit in sectionUnits) {
      findings += findingsByUnit[unit.key] ?? 0;
      high += highByUnit[unit.key] ?? 0;
      final score = result.scores[unit.key];
      if (score != null) {
        reviewedHere++;
        scored.add(
          UnitScore(
            key: unit.key,
            id: unit.id,
            title: unit.title,
            score: score,
            findingCount: findingsByUnit[unit.key] ?? 0,
          ),
        );
      }
    }
    if (findings == 0 && scored.isEmpty) return; // nothing to say
    scored.sort((a, b) => a.score.compareTo(b.score));
    final average = scored.isEmpty
        ? null
        : scored.fold<int>(0, (sum, u) => sum + u.score) / scored.length;
    scores.add(
      SectionScore(
        section: name,
        reviewedCount: reviewedHere,
        averageScore: average,
        findingCount: findings,
        highSeverityCount: high,
        units: List.unmodifiable(scored),
      ),
    );
  });

  scores.sort((a, b) {
    // Dart's List.sort is not stable, so every comparison here ends in a
    // total order (finding count, then name) — otherwise tied sections would
    // swap rows between renders and the expand-by-name state would follow
    // the wrong row.
    final left = a.averageScore, right = b.averageScore;
    if (left != null && right != null) {
      final byAverage = left.compareTo(right);
      if (byAverage != 0) return byAverage;
    } else if (left != null) {
      return -1; // scored sections rank above unscored
    } else if (right != null) {
      return 1;
    }
    final byFindings = b.findingCount.compareTo(a.findingCount);
    if (byFindings != 0) return byFindings;
    if (a.highSeverityCount != b.highSeverityCount) {
      return b.highSeverityCount.compareTo(a.highSeverityCount);
    }
    return a.section.compareTo(b.section);
  });
  return List.unmodifiable(scores);
}
