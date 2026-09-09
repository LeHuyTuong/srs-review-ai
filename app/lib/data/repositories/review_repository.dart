/// Drives the review of a whole document, one requirement at a time
/// (per-requirement keeps the JSON stable — research 07 §6.2).
///
/// Emits [ReviewProgress] so the UI can show real stage labels instead of a
/// spinner, and supports cancellation via a single [CancelToken].
library;

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../models/review_models.dart';
import '../models/srs_document.dart';
import '../services/api_service.dart';
import '../services/review_api.dart';

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
  });

  final ReviewStage stage;
  final int completed;
  final int total;
  final String? currentRequirementId;
  final String? error;

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
  const ReviewRun({required this.results, required this.failures});

  final Map<String, ReviewResult> results;

  /// requirement id -> reason, so one bad requirement cannot abort the run.
  final Map<String, String> failures;

  bool get isEmpty => results.isEmpty;

  int get totalIssues =>
      results.values.fold(0, (sum, r) => sum + r.issues.length);

  int get totalDropped =>
      results.values.fold(0, (sum, r) => sum + r.droppedIssueCount);

  int countBySeverity(Severity severity) =>
      results.values.fold(0, (sum, r) => sum + r.countBySeverity(severity));

  /// Mean requirement score, on the same 0–10 scale the course uses.
  double get overallScore {
    if (results.isEmpty) return 0;
    final total = results.values.fold<int>(0, (sum, r) => sum + r.score);
    return total / results.length;
  }
}

class ReviewRepository {
  ReviewRepository(this._api);

  final ReviewApi _api;
  CancelToken? _cancelToken;

  bool get isRunning => _cancelToken != null && !_cancelToken!.isCancelled;

  void cancel() {
    _cancelToken?.cancel('cancelled by user');
    _cancelToken = null;
  }

  /// Reviews every requirement, yielding progress as it goes. The final event
  /// is always [ReviewStage.done], [ReviewStage.cancelled] or
  /// [ReviewStage.failed].
  Stream<ReviewProgress> run(
    SrsDocument document, {
    required void Function(ReviewRun run) onComplete,
  }) async* {
    final items = document.requirements
        .take(AppConfig.maxRequirementsPerRun)
        .toList();
    final token = CancelToken();
    _cancelToken = token;

    final results = <String, ReviewResult>{};
    final failures = <String, String>{};

    yield ReviewProgress(stage: ReviewStage.parsing, total: items.length);

    for (var i = 0; i < items.length; i++) {
      if (token.isCancelled) {
        _cancelToken = null;
        onComplete(ReviewRun(results: results, failures: failures));
        yield ReviewProgress(
          stage: ReviewStage.cancelled,
          completed: results.length,
          total: items.length,
        );
        return;
      }

      final item = items[i];
      yield ReviewProgress(
        stage: ReviewStage.reviewing,
        completed: i,
        total: items.length,
        currentRequirementId: item.id,
      );

      try {
        results[item.id] = await _api.review(
          requirementId: item.id,
          text: item.text,
          section: item.section,
          pageIndex: item.pageIndex,
          cancelToken: token,
        );
      } on ApiException catch (error) {
        // A quota or provider error kills the whole run; a single bad
        // requirement does not.
        if (error.statusCode == 429 || error.statusCode == 401) {
          _cancelToken = null;
          onComplete(ReviewRun(results: results, failures: failures));
          yield ReviewProgress(
            stage: ReviewStage.failed,
            completed: results.length,
            total: items.length,
            error: error.message,
          );
          return;
        }
        failures[item.id] = error.message;
      } on ContractException catch (error) {
        failures[item.id] = error.message;
      }
    }

    _cancelToken = null;
    yield ReviewProgress(
      stage: ReviewStage.verifying,
      completed: results.length,
      total: items.length,
    );
    onComplete(ReviewRun(results: results, failures: failures));
    yield ReviewProgress(
      stage: ReviewStage.done,
      completed: results.length,
      total: items.length,
    );
  }

  Future<AskResponse> ask({
    required String question,
    required SrsDocument document,
  }) => _api.ask(question: question, context: document.fullText);
}
