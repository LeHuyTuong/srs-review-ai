/// Drives the review of a whole document, several requirements at a time.
///
/// Requirements are reviewed concurrently because a sequential loop made a
/// 40-unit run take minutes of wall time while the UI had nothing to show —
/// the worst UX defect in the app (see docs/uiux/audit-2026-09-11.md). Bounded
/// concurrency keeps the proxy and the provider quota comfortable while cutting
/// the wait by roughly the pool size.
///
/// Emits [ReviewProgress] so the UI can show real stage labels instead of a
/// spinner, and supports cancellation via a single [CancelToken].
library;

import 'dart:async';

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
    this.skipped = 0,
  });

  final Map<String, ReviewResult> results;

  /// requirement id -> reason, so one bad requirement cannot abort the run.
  final Map<String, String> failures;

  /// Units the per-run cap excluded. Surfaced to the user, never swallowed.
  final int skipped;

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
  ///
  /// [concurrency] is bounded: every in-flight request costs a provider call,
  /// so a document-wide fan-out would be neither kind to the quota nor useful
  /// to someone reading a progress bar.
  Stream<ReviewProgress> run(
    SrsDocument document, {
    required void Function(ReviewRun run) onComplete,
    int concurrency = AppConfig.reviewConcurrency,
  }) {
    // The controller is closed by _drive when the run ends; closing it here
    // would end the stream before it ever starts.
    // ignore: close_sinks
    final controller = StreamController<ReviewProgress>();
    unawaited(
      _drive(
        document: document,
        controller: controller,
        onComplete: onComplete,
        concurrency: concurrency.clamp(1, 8),
      ),
    );
    return controller.stream;
  }

  Future<void> _drive({
    required SrsDocument document,
    required StreamController<ReviewProgress> controller,
    required void Function(ReviewRun run) onComplete,
    required int concurrency,
  }) async {
    final all = document.requirements;
    final items = all
        .take(AppConfig.maxRequirementsPerRun)
        .toList(growable: false);

    // The per-run cap is real, so it is accounted for instead of being
    // applied behind the user's back. `skipped` rides on every progress event
    // and lands in the UI banner.
    final skipped = all.length - items.length;

    final token = CancelToken();
    _cancelToken = token;

    final results = <String, ReviewResult>{};
    final failures = <String, String>{};
    var next = 0;
    var completed = 0;
    var killed = false;
    var cancelled = false;
    String? killMessage;

    void emit(ReviewProgress progress) {
      if (!controller.isClosed) controller.add(progress);
    }

    emit(
      ReviewProgress(
        stage: ReviewStage.parsing,
        total: items.length,
        skipped: skipped,
      ),
    );

    Future<void> worker() async {
      while (true) {
        if (killed || token.isCancelled) {
          cancelled = token.isCancelled;
          return;
        }
        final index = next++;
        if (index >= items.length) return;
        final item = items[index];

        emit(
          ReviewProgress(
            stage: ReviewStage.reviewing,
            completed: completed,
            total: items.length,
            currentRequirementId: item.id,
            skipped: skipped,
          ),
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
            killed = true;
            killMessage = error.message;
            return;
          }
          failures[item.id] = error.message;
        } on ContractException catch (error) {
          failures[item.id] = error.message;
        } on Object catch (error) {
          // A worker must never die silently and strand the progress bar.
          failures[item.id] = '$error';
        }

        completed++;
        emit(
          ReviewProgress(
            stage: ReviewStage.reviewing,
            completed: completed,
            total: items.length,
            skipped: skipped,
          ),
        );
      }
    }

    final pool = [
      for (var i = 0; i < concurrency && i < items.length; i++) worker(),
    ];
    await Future.wait(pool);

    final run = ReviewRun(
      results: results,
      failures: failures,
      skipped: skipped,
    );
    _cancelToken = null;

    if (killed) {
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.failed,
          completed: results.length,
          total: items.length,
          skipped: skipped,
          error: killMessage,
        ),
      );
    } else if (cancelled || token.isCancelled) {
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.cancelled,
          completed: results.length,
          total: items.length,
          skipped: skipped,
        ),
      );
    } else {
      emit(
        ReviewProgress(
          stage: ReviewStage.verifying,
          completed: results.length,
          total: items.length,
          skipped: skipped,
        ),
      );
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.done,
          completed: results.length,
          total: items.length,
          skipped: skipped,
        ),
      );
    }

    await controller.close();
  }

  Future<AskResponse> ask({
    required String question,
    required SrsDocument document,
  }) => _api.ask(question: question, context: document.fullText);
}
