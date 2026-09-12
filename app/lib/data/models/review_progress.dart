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

bool _mapsEqual(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) return false;
  return left.entries.every((entry) => right[entry.key] == entry.value);
}

bool _setsEqual(Set<String> left, Set<String> right) {
  return left.length == right.length && left.every(right.contains);
}

int _mapHash(Map<String, int> value) {
  final hashes =
      value.entries.map((entry) => Object.hash(entry.key, entry.value)).toList()
        ..sort();
  return Object.hashAll(hashes);
}

int _setHash(Set<String> value) {
  final hashes = value.toList()..sort();
  return Object.hashAll(hashes);
}

class PageImageCoverage {
  const PageImageCoverage({
    this.candidates = 0,
    this.extracted = 0,
    this.reviewed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.reasons = const <String, int>{},
    this.decisions = const <String, int>{},
    this.reviewedOccurrenceKeys = const <String>{},
  });

  /// Requirements with diagram intent and a candidate page, including pages
  /// later deferred by the run budget.
  final int candidates;

  /// Requirements whose selected page was rendered and base64-encoded inside
  /// the request guard. A shared page counts once per requirement that can use
  /// its bytes.
  final int extracted;

  /// Requirements whose successful review request actually carried an image.
  final int reviewed;

  /// Requirements that were not successfully image-reviewed. This intentionally
  /// includes ordinary text-only requirements so `reviewed + skipped == total`.
  final int skipped;

  /// Selected requirements whose image preparation or image-bearing request
  /// failed. Ordinary text-only requirements are not renderer failures.
  final int failed;

  /// Stable fallback/decision tokens -> requirement counts.
  final Map<String, int> reasons;

  /// [PageImageDecision.name] -> requirement counts.
  final Map<String, int> decisions;

  /// Occurrence keys whose successful request included `imageB64`.
  final Set<String> reviewedOccurrenceKeys;

  @override
  bool operator ==(Object other) {
    return other is PageImageCoverage &&
        other.candidates == candidates &&
        other.extracted == extracted &&
        other.reviewed == reviewed &&
        other.skipped == skipped &&
        other.failed == failed &&
        _mapsEqual(other.reasons, reasons) &&
        _mapsEqual(other.decisions, decisions) &&
        _setsEqual(other.reviewedOccurrenceKeys, reviewedOccurrenceKeys);
  }

  @override
  int get hashCode => Object.hash(
    candidates,
    extracted,
    reviewed,
    skipped,
    failed,
    _mapHash(reasons),
    _mapHash(decisions),
    _setHash(reviewedOccurrenceKeys),
  );
}

class ReviewRun {
  const ReviewRun({
    required this.results,
    required this.failures,
    required this.stage,
    this.failureRequirementIds = const {},
    this.skipped = 0,
    this.imageCoverage = const PageImageCoverage(),
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

  /// Page-image selection, extraction, and transmission coverage for this run.
  final PageImageCoverage imageCoverage;

  int get totalDropped =>
      results.values.fold(0, (sum, r) => sum + r.droppedIssueCount);
}
