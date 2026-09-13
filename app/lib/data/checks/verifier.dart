/// Round 9 — Verifier that promotes a finding's [FindingStatus] after a
/// fresh deterministic re-run, encoding goal §3 invariants as code:
///
///   - rule 2: a status moves to [FindingStatus.verified] only when the
///     fresh check no longer fires for that finding. "I think I fixed it"
///     is not evidence; the deterministic run is.
///   - rule 3: a finding whose target is only reachable via the vision
///     pipeline is written as [FindingStatus.pendingVision] instead of
///     [FindingStatus.open], so the row never silently turns green.
///
/// The Verifier is a pure function over three inputs: the previous status
/// map (id → status), the fresh syllabus findings, and the fresh M2
/// reference findings. It returns the next status map. No I/O, no LLM, no
/// clock — safe to call from a widget test or from a re-run button in
/// the UI.
///
/// Stability invariant (rule 1, goal §3): the Verifier never re-numbers
/// or re-uses ids. It only touches [FindingStatus]. A finding that
/// disappears from the new failure set is "still in the ledger" — it
/// just gets a new status. The dashboard continues to render the row
/// under its original id, marked verified.
library;

import '../../features/workspace/models/workspace_findings.dart';
import '../models/deterministic_finding.dart';

class Verifier {
  const Verifier();

  /// Returns the new status map after a deterministic re-run.
  ///
  /// Inputs:
  ///   - [previousStatuses]: id → status, from the last saved snapshot
  ///     or from a fresh import. May contain BOTH deterministic keys
  ///     (`<wire>:<subject>`) and AI finding ids (`SEQ-CLS-01`); the
  ///     AI ids are passed through unchanged because no deterministic
  ///     re-run can produce evidence to transition them.
  ///   - [syllabusFindings]: fresh F7/F8/F9 results.
  ///   - [referenceFindings]: fresh M2 results (duplicate ids, missing
  ///     postconditions).
  ///
  /// Output: id → status, with at minimum every id from
  /// `previousStatuses` carried forward (rule 1) and every fresh
  /// failure listed under its key.
  Map<String, FindingStatus> verify({
    required Map<String, FindingStatus> previousStatuses,
    required List<DeterministicFinding> syllabusFindings,
    required List<DeterministicFinding> referenceFindings,
  }) {
    // The set of keys that fire in the fresh run. Anything not in this
    // set has either been fixed or was never failing.
    final stillFailing = <String>{
      for (final f in _failingFindings(syllabusFindings)) _keyOf(f),
      for (final f in _failingFindings(referenceFindings)) _keyOf(f),
    };

    // Promote / demote every previous status by the new evidence, but
    // only for the deterministic subset — AI finding ids carry a
    // verdict the deterministic path cannot re-derive, so they pass
    // through untouched (rule 3's spirit: a verdict the system did
    // not produce cannot be auto-overridden by the system either).
    final next = <String, FindingStatus>{};
    previousStatuses.forEach((id, status) {
      if (!isDeterministicFindingKey(id)) {
        next[id] = status;
        return;
      }
      final isFailing = stillFailing.contains(id);
      next[id] = _transition(status: status, isFailing: isFailing);
    });

    // For every fresh failure we have not seen before, open it.
    // UNV rows (requiresVisionEvidence) start as pendingVision — the
    // brief says vision-required findings must never be tinted green,
    // so they begin in the limbo state and the Verifier's transition
    // table promotes them only when the text-only path confirms.
    final visionRequired = <String>{
      for (final f in _failingFindings(syllabusFindings)
        .followedBy(_failingFindings(referenceFindings)))
        if (f.requiresVisionEvidence) _keyOf(f),
    };
    for (final key in stillFailing) {
      if (next.containsKey(key)) continue;
      next[key] =
          visionRequired.contains(key) ? FindingStatus.pendingVision : FindingStatus.open;
    }
    return next;
  }

  // ---------------------------------------------------------------------
  // helpers

  static List<DeterministicFinding> _failingFindings(
    List<DeterministicFinding> findings,
  ) => findings.where((f) => !f.passed).toList(growable: false);

  /// Stable key across runs. Two findings with the same `check.wire`
  /// and `subject` are the same finding — even if the message wording
  /// changed between runs (the parser may have re-worded a sentence).
  static String _keyOf(DeterministicFinding f) =>
      '${f.check.wire}:${f.subject ?? '_'}';

  /// One-step transition per goal §3 rule 2 and rule 3.
  ///
  /// Rule 2 (verified needs evidence):
  ///   - fixed + not failing    → verified
  ///   - fixed + still failing  → open (the fix didn't hold)
  ///   - open + not failing     → verified (silent fix: the check no
  ///                              longer fires, so the row moves on)
  ///   - open + still failing   → open (no change)
  ///   - verified + still failing → open (regression: a verifier put it
  ///                                here, the next run contradicts)
  ///   - verified + not failing → verified (stays)
  ///   - pendingVision + not failing → verified (the text-only path now
  ///                                    decides; the goal becomes
  ///                                    reachable)
  ///   - pendingVision + still failing → pendingVision (still waiting)
  ///   - disputed → disputed in both branches (a user dispute stands
  ///                until the user re-categorises the row, per goal §3
  ///                rule 3's spirit: a contested row must never be
  ///                auto-promoted)
  static FindingStatus _transition({
    required FindingStatus status,
    required bool isFailing,
  }) {
    if (status == FindingStatus.disputed) return FindingStatus.disputed;
    if (status == FindingStatus.pendingVision) {
      return isFailing ? FindingStatus.pendingVision : FindingStatus.verified;
    }
    if (status == FindingStatus.fixed) {
      return isFailing ? FindingStatus.open : FindingStatus.verified;
    }
    if (status == FindingStatus.verified) {
      return isFailing ? FindingStatus.open : FindingStatus.verified;
    }
    // status == FindingStatus.open
    return isFailing ? FindingStatus.open : FindingStatus.verified;
  }
}