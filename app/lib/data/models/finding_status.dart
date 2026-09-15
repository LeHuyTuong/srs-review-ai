/// The finding lifecycle enum — the five-state ledger contract from goal §3.
///
/// This file used to live in `features/workspace/models/workspace_findings.dart`,
/// which forced `data/checks/verifier.dart` to import UP from the data layer
/// into features — a standing MVVM layering violation (guardrail
/// `data-no-features`). The enum is pure data with zero feature dependencies,
/// so it belongs one layer down, next to `deterministic_finding.dart` which
/// already speaks about findings. `workspace_findings.dart` re-exports it, so
/// every existing `import 'workspace_findings.dart'` keeps resolving the name.
library;

/// Where a finding stands with the person who has to act on it.
///
/// The five-state ledger is the contract from goal §3: every finding has
/// exactly one of these five states, and the meaning of each is encoded
/// here so a dashboard rebuild can never drift from the schema.
///
/// State flow (who can move into it):
///   - open          user / verifier / system (default)
///   - fixed         user has applied a fix in the source document
///   - verified      verifier only — checker ran again and the finding
///                   no longer fires (NEVER set by a user click)
///   - pendingVision verifier only — text-based checkers cannot decide
///                   without a diagram or screenshot
///   - disputed      user judges this a false positive
///
/// Wire format uses the enum `.name` (lowerCamel), with two legacy
/// aliases accepted by [fromName] so workspaces saved by Round ≤7
/// (which used `accepted` / `dismissed`) open with the same behaviour
/// they always had — accepted reads as fixed, dismissed as disputed.
enum FindingStatus {
  /// Not acted on yet.
  open,

  /// Author applied a fix in the source document; the next verifier
  /// run will confirm by either dropping the finding (→ [verified]) or
  /// re-surfacing it (→ [open]).
  fixed,

  /// Re-run of the deterministic checker (or a vision re-pass that
  /// actually opens the diagram) confirmed the finding no longer fires.
  /// Goal §3 rule: this is the only way out of [fixed] that counts as
  /// done.
  verified,

  /// The text-only path could not decide — needs a diagram or a human
  /// reading the model. Per goal §3, an unverified target stays in this
  /// row forever; it must never be silently promoted to [verified].
  pendingVision,

  /// Author disputes the finding as a false positive. Kept, never
  /// deleted — the report still shows it, marked, so a dismissed
  /// finding cannot quietly disappear from the evidence.
  disputed;

  String get label => switch (this) {
    FindingStatus.open => 'Open',
    FindingStatus.fixed => 'Fixed',
    FindingStatus.verified => 'Verified',
    FindingStatus.pendingVision => 'Pending vision',
    FindingStatus.disputed => 'Disputed',
  };

  static FindingStatus fromName(String? name) {
    // Legacy aliases from Round ≤7. Once every persisted session has
    // been re-saved (no migration script needed — they all auto-upgrade
    // on first open) these branches can be removed.
    switch (name) {
      case 'accepted':
        return FindingStatus.fixed;
      case 'dismissed':
        return FindingStatus.disputed;
    }
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => FindingStatus.open,
    );
  }
}
