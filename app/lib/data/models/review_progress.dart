/// Progress and outcome values for a review run.
///
/// These used to live inside `data/repositories/review_repository.dart`, which
/// meant a *view* that only wanted the `ReviewStage` enum had to import a
/// repository — a widget depending on the data layer's transport-facing class.
/// They are plain values, so they belong with the other models.
library;

import 'review_models.dart';

enum ReviewStage {
  idle,
  parsing,
  reviewing,
  verifying,
  done,
  cancelled,
  failed,
}

class ReviewProgress {
  const ReviewProgress({
    required this.stage,
    this.completed = 0,
    this.total = 0,
    this.currentRequirementId,
    this.error,
    this.skipped = 0,
  });

  final ReviewStage stage;
  final int completed;
  final int total;
  final String? currentRequirementId;
  final String? error;

  /// Requirements the per-run cap left out of this run. Non-zero means the
  /// button's promise and the work actually done disagree, so the UI owes the
  /// user the difference in plain words.
  final int skipped;

  double get fraction => total == 0 ? 0 : completed / total;

  String get label => switch (stage) {
    ReviewStage.idle => 'Ready',
    ReviewStage.parsing => 'Splitting requirements…',
    ReviewStage.reviewing =>
      'Reviewing $completed/$total${currentRequirementId == null ? '' : ' ($currentRequirementId)'}…',
    ReviewStage.verifying => 'Verifying quotes…',
    ReviewStage.done => 'Done — $completed requirements reviewed',
    ReviewStage.cancelled => 'Cancelled',
    ReviewStage.failed => error ?? 'Review failed',
  };
}

class ReviewRun {
  const ReviewRun({
    required this.results,
    required this.failures,
    required this.stage,
    this.failureRequirementIds = const {},
    this.skipped = 0,
  });

  /// occurrence key -> review result; raw [ReviewResult.requirementId] values may repeat.
  final Map<String, ReviewResult> results;

  /// occurrence key -> reason, so repeated raw requirement IDs remain distinct.
  final Map<String, String> failures;

  /// occurrence key -> raw requirement ID, used by the UI when displaying failures.
  final Map<String, String> failureRequirementIds;

  /// How the run ended: [ReviewStage.done], [ReviewStage.cancelled] or
  /// [ReviewStage.failed]. Consumers must mark a unit "reviewed" only when
  /// its occurrence key is in `results`; this field says what happened to the
  /// rest, so a killed or cancelled run can never masquerade as a complete one.
  final ReviewStage stage;

  /// Units the per-run cap excluded. Surfaced to the user, never swallowed.
  final int skipped;

  int get totalDropped =>
      results.values.fold(0, (sum, r) => sum + r.droppedIssueCount);
}
