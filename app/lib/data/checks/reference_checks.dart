/// M2 reference checks — the deterministic side of "global review".
///
/// Where `SyllabusChecks` measures the document against the syllabus
/// thresholds (F7/F8/F9), these checks measure internal consistency: an id
/// reused across two distinct requirement rows, a use case table that never
/// declares a Postcondition. No LLM, no network — pure pattern over the
/// already-parsed [SrsDocument].
///
/// Their shape matches F7/F8/F9 exactly (`DeterministicFinding`), so they
/// land in the same dashboard surface and the same export pipeline without
/// any UI work. New IDs were added to the [CheckId] enum and to
/// `contracts/review.schema.json` (1.0.0 → 1.1.0), so anything that persists
/// a finding to disk will round-trip these new entries without a schema
/// migration.
///
/// Why this lives next to [SyllabusChecks] and not inside it: the syllabus
/// family is **provisional** until the official marking sheet arrives, while
/// duplicate-id and missing-postcondition are **stable** smells a generic SRS
/// almost always carries. Separating the families also keeps the syllabus
/// tests free of these new entries, so a bump here will not light up the F7
/// suite.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';

class ReferenceChecks {
  const ReferenceChecks();

  /// Runs every M2 reference check and returns findings in document order.
  ///
  /// Always returns a list (never null); an empty list means the document
  /// is "clean" against this family. Findings come out grouped per check so
  /// the dashboard can show one section per smell type.
  List<DeterministicFinding> runAll(SrsDocument document) => [
    ...duplicateIds(document),
    ...missingPostcondition(document),
    ...missingActor(document),
  ];

  // ---------------------------------------------------------------- duplicateIds
  /// Reports every explicit id that two or more requirements share.
  ///
  /// The same id appearing on multiple rows is **not** always wrong — UC04
  /// legitimately labels several use-case tables in some templates — but the
  /// reader has to confirm it on purpose. We surface the count and let the
  /// user dismiss the finding if reuse was intended (the existing
  /// `FindingStatus.disputed` flow handles that — only the source data type
  /// differs).
  List<DeterministicFinding> duplicateIds(SrsDocument document) {
    final grouped = <String, int>{};
    for (final item in document.requirements) {
      // We only care about explicit ids (UC-xx, FR-xx, etc.). Bare-modal
      // statements and section units are given synthetic ids by the
      // splitter and are not the reuse signal we are looking for.
      if (item.kind == RequirementKind.statement || item.hasSyntheticId) {
        continue;
      }
      grouped.update(item.id, (n) => n + 1, ifAbsent: () => 1);
    }
    final findings = <DeterministicFinding>[];
    final sortedIds = grouped.keys.where((id) => grouped[id]! > 1).toList()
      ..sort();
    for (final id in sortedIds) {
      final occurrences = grouped[id]!;
      findings.add(
        DeterministicFinding(
          check: CheckId.duplicateIds,
          passed: false,
          severity: Severity.high,
          message:
              'Id "$id" is used by $occurrences requirements. Reuse is a '
              'signal, not always a bug — confirm the duplication on purpose.',
          subject: id,
          actual: occurrences,
        ),
      );
    }
    return findings;
  }

  // ---------------------------------------------------------------- missingPostcondition
  /// Reports every use case whose requirement text does not declare a
  /// Postcondition (or its bilingual equivalent "điều kiện sau").
  ///
  /// The marker is the heading line: a bare "Postcondition." counts; a
  /// sentence mid-paragraph that *uses* the word does not, because the
  /// goal is a **declarable end-state** a tester can verify, not a mention.
  /// Matches both one-word and hyphenated spellings (`post-condition`,
  /// `post condition`, `postconditions`) plus the VN form
  /// `điều kiện sau (thành công|kết thúc|…)`.
  static final RegExp _postconditionHeading = RegExp(
    r'^[\s\-•*|]*'
    r'(?:post[\s\-]?conditions?|điều\s*kiện\s*sau)'
    r'\s*[:.\-–—|]',
    caseSensitive: false,
    multiLine: true,
  );

  List<DeterministicFinding> missingPostcondition(SrsDocument document) {
    final findings = <DeterministicFinding>[];
    // Sort by id so the dashboard rows are stable across runs — required
    // by the ledger invariant "id-stable, never reorder after publish".
    final useCases = document.requirements.where((r) => r.isUseCase).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final uc in useCases) {
      if (_postconditionHeading.hasMatch(uc.text)) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.missingPostcondition,
          passed: false,
          severity: Severity.high,
          message:
              'Use case "$uc" has no Postcondition section. Without a '
              'measurable end-state the tester cannot tell when the flow is '
              'done.',
          subject: uc.id,
        ),
      );
    }
    return findings;
  }

  // ---------------------------------------------------------------- missingActor

  /// Round 13 — reports every use case whose requirement text does not
  /// name an actor. A use case without an actor leaves the system
  /// boundary undefined: the flow has no "who" — was it a human, another
  /// system, or time? The marker is the **heading** row, exactly like
  /// [missingPostcondition]: a bare "Actor:" line counts, a sentence
  /// mid-paragraph that *uses* the word does not.
  ///
  /// Matches both English (`Actor`, `Primary actor`) and Vietnamese
  /// (`Tác nhân`, `Người dùng`, `Actor chính`) labels. OTES is
  /// Vietnamese, so the regex has to be bilingual — otherwise the check
  /// silently returns 0 on a 28.7 MB document full of UCs and the
  /// reader concludes "no actor smells, all good", which is the
  /// exact opposite of the truth.
  static final RegExp _actorHeading = RegExp(
    r'^[\s\-•*|]*'
    r'(?:primary\s+)?actors?|tác\s*nhân|người\s*dùng(?:\s+chính)?'
    r'\s*[:.\-–—|]',
    caseSensitive: false,
    multiLine: true,
  );

  List<DeterministicFinding> missingActor(SrsDocument document) {
    final findings = <DeterministicFinding>[];
    // Sort by id for the same ledger-stability reason as
    // [missingPostcondition].
    final useCases = document.requirements.where((r) => r.isUseCase).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final uc in useCases) {
      if (_actorHeading.hasMatch(uc.text)) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.missingActor,
          passed: false,
          severity: Severity.high,
          message:
              'Use case "$uc" has no Actor label. A use case without an '
              'actor leaves the system boundary undefined — the flow has '
              'no "who".',
          subject: uc.id,
        ),
      );
    }
    return findings;
  }
}
