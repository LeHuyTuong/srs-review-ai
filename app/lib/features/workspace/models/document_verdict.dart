/// Feature 2: the sds-reviewer 10-point scale (rubric Mục E), computed
/// from ledger rows only — zero tokens, zero network, deterministic.
///
/// Mục E verbatim (`sds-reviewer/references/rubric.md`):
///   Sàn 5: rubric A đủ 7 mục
///   +2: diagram pass — notation đúng, không lỗi nghiêm trọng từng ảnh
///   +2: cross-artifact pass — 0 🔴 mục B, FK matrix sạch
///   +1: traceability thật (UC→design→test)
///   Múc trừ: −1 mỗi 🔴 FLOW/ERD ảnh hưởng dữ liệu thật
///
/// HONEST DEVIATIONS (the app reviews SRS, not SDS — see
/// docs/evidence/rubric-vs-skills-map.md row 4):
///  * "rubric A 7 mục" is an SDS structure checklist. Its SRS analogue in
///    this app is the seven deterministic buckets in [floorCriteria] —
///    each named after the quality criterion it proves, not after an SDS
///    section the document class does not have.
///  * traceability (UC→design→test) can never be earned yet: there is no
///    test-artifact parser in the app, so [TraceabilityComponent] is
///    null for every input. Not a TODO — a documented permanent null
///    until feature 1-style cross-document data exists. Ceiling today
///    is therefore 9, and the render says so.
///  * deductions count per LEDGER ROW (one audited page), not per red
///    finding on the page: a page with three red FK lines costs −1, not
///    −3. Conservative relative to the rubric; measured on the batch of
///    2026-09-14 where p180 carried three reds in one row.
library;

import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/review_models.dart' show Severity;

/// One named bucket of the floor: what it proves, which checks prove it.
class FloorCriterion {
  const FloorCriterion(this.name, this.checks);

  /// Human-readable criterion (mirrors an IEEE-830 quality criterion).
  final String name;

  /// Checks that must ALL have run; the criterion passes when none of
  /// them carries a failed row.
  final List<CheckId> checks;
}

/// The seven SRS-analogue criteria. Kept as data so a wrong mapping
/// shows up as exactly one failed test on exactly one criterion.
const List<FloorCriterion> floorCriteria = [
  FloorCriterion('count plausible', [CheckId.ucCount]),
  FloorCriterion('uc granularity', [CheckId.ucSize]),
  FloorCriterion('language', [CheckId.language]),
  FloorCriterion('unambiguous', [CheckId.ambiguousWording]),
  FloorCriterion('complete', [
    CheckId.placeholderTbd,
    CheckId.missingPostcondition,
    CheckId.missingActor,
  ]),
  // duplicateIds only: crossArtifactName lives in its own +2 bucket, and
  // scoring the same rows twice would inflate the total past the rubric.
  FloorCriterion('consistent', [CheckId.duplicateIds]),
  FloorCriterion('prioritized', [CheckId.missingPriority]),
];

/// State of one score component: earned / failed / not assessable.
enum ComponentState { passed, failed, unassessed }

/// The full verdict. [total] is null unless the floor is assessable —
/// a number without a floor would be a fabrication.
class DocumentVerdict {
  const DocumentVerdict({
    required this.floor,
    required this.diagram,
    required this.crossArtifact,
    required this.traceability,
    required this.deductions,
    required this.earnedPoints,
    required this.unassessedCount,
  });

  static const int floorPoints = 5;
  static const int bonusPoints = 2;
  static const int traceabilityPoints = 1;

  final ComponentState floor;
  final ComponentState diagram;
  final ComponentState crossArtifact;
  final ComponentState traceability;

  /// Count of deducted rows (each −1).
  final int deductions;

  /// Raw score before clamping; null when the floor is unassessed.
  final int? earnedPoints;

  /// How many of the four components rendered as "unassessed".
  final int unassessedCount;

  /// Clamped 0..10, or null when unassessable.
  int? get total => earnedPoints?.clamp(0, 10);

  /// "9/10 (partial — 1 component unassessed)" / "7/10" / "unassessed".
  String get display {
    final t = total;
    if (t == null) return 'unassessed (no deterministic checks have run yet)';
    if (unassessedCount == 0) return '$t/10';
    return '$t/10 (partial — $unassessedCount component'
        '${unassessedCount == 1 ? '' : 's'} unassessed)';
  }

  Map<String, Object?> toJson() => {
    'total': total,
    'display': display,
    'floor': floor.name,
    'diagram': diagram.name,
    'cross_artifact': crossArtifact.name,
    'traceability': traceability.name,
    'deductions': deductions,
  };
}

/// Compute the Mục E score from ledger rows. Pure and total: any row set
/// (including empty) yields a verdict, never throws.
DocumentVerdict computeVerdict(List<DeterministicFinding> rows) {
  bool ran(CheckId c) => rows.any((r) => r.check == c);
  bool anyFail(CheckId c) =>
      rows.any((r) => r.check == c && !r.passed);

  // Floor: every criterion must be assessable (all its checks ran) and
  // none failed. One failed criterion → floor lost (the "5" is all-or-
  // nothing, exactly like the rubric's wording "đủ 7 mục").
  final floorAssessable = floorCriteria.every(
    (crit) => crit.checks.every(ran),
  );
  final floorEarned = floorAssessable &&
      floorCriteria.every((crit) => !crit.checks.any(anyFail));
  final floor = !floorAssessable
      ? ComponentState.unassessed
      : floorEarned
      ? ComponentState.passed
      : ComponentState.failed;

  // +2 diagram: needs audited pages; any high row (≥1 red finding) fails.
  final diagramRows = rows.where((r) => r.check == CheckId.diagramAudit);
  final ComponentState diagram;
  if (diagramRows.isEmpty) {
    diagram = ComponentState.unassessed;
  } else {
    diagram = diagramRows.every((r) => r.passed)
        ? ComponentState.passed
        : ComponentState.failed;
  }

  // +2 cross-artifact: the naming-drift chain. FK matrix / seq↔class /
  // status-vocabulary chains are not implemented (1/6 chain, map row 6),
  // so passing this earns the bonus only against what CAN be checked —
  // the deviation is recorded here and in the plan, not hidden.
  final xRows = rows.where((r) => r.check == CheckId.crossArtifactName);
  final ComponentState crossArtifact;
  if (xRows.isEmpty) {
    crossArtifact = ComponentState.unassessed;
  } else {
    crossArtifact = xRows.every((r) => r.passed)
        ? ComponentState.passed
        : ComponentState.failed;
  }

  // +1 traceability: no test-artifact input exists in this app.
  const traceability = ComponentState.unassessed;

  // −1 each: diagram rows with reds (high) whose family is ERD or FLOW.
  final deductionRows = diagramRows.where(
    (r) =>
        !r.passed &&
        r.severity == Severity.high &&
        ((r.subject ?? '').startsWith('ERD-') ||
            (r.subject ?? '').startsWith('FLOW-')),
  );
  final deductions = deductionRows.length;

  final unassessed = [floor, diagram, crossArtifact, traceability]
      .where((c) => c == ComponentState.unassessed)
      .length;

  final int? earned;
  if (floor == ComponentState.unassessed) {
    earned = null;
  } else {
    var p = floor == ComponentState.passed ? DocumentVerdict.floorPoints : 0;
    if (diagram == ComponentState.passed) p += DocumentVerdict.bonusPoints;
    if (crossArtifact == ComponentState.passed) {
      p += DocumentVerdict.bonusPoints;
    }
    if (traceability == ComponentState.passed) {
      p += DocumentVerdict.traceabilityPoints;
    }
    earned = p - deductions;
  }

  return DocumentVerdict(
    floor: floor,
    diagram: diagram,
    crossArtifact: crossArtifact,
    traceability: traceability,
    deductions: deductions,
    earnedPoints: earned,
    unassessedCount: unassessed,
  );
}
