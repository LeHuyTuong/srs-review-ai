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
import '../models/review_progress.dart';
import '../models/srs_document.dart';
import '../services/api_service.dart';
import '../services/image_budget.dart';
import '../services/page_image_selector.dart';
import '../services/review_api.dart';

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
    final candidatePages = document.imagePageIndexes.toSet();
    final pageImageSelector = PageImageSelector(budget: ImageBudget());

    // The per-run cap is real, so it is accounted for instead of being
    // applied behind the user's back. `skipped` rides on every progress event
    // and lands in the UI banner.
    final skipped = all.length - items.length;

    final occurrenceKeys = <String>[
      for (var index = 0; index < items.length; index++)
        index < document.occurrenceKeys.length &&
                (document.occurrenceKeys.length == items.length ||
                    document.occurrenceKeys.length == all.length)
            ? document.occurrenceKeys[index]
            : 'u$index-${items[index].id}',
    ];

    final token = CancelToken();
    _cancelToken = token;

    final results = <String, ReviewResult>{};
    final failures = <String, String>{};
    final failureRequirementIds = <String, String>{};
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
        final occurrenceKey = occurrenceKeys[index];
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

        // Plan once per item before retries. M4 v0 reserves selected pages,
        // but every decision still uses the existing text-only request until
        // the renderer is wired.
        pageImageSelector.planFor(
          requirementId: occurrenceKey,
          text: item.text,
          pageIndex: item.pageIndex,
          candidatePages: candidatePages,
        );

        // Retry only what is worth retrying. `isRetryable` has been set on
        // ApiException since day one but nothing ever read it, so a dropped
        // connection or a 90s timeout cost a requirement outright and the run
        // marched on — a whole document could lose units to a brief blip and
        // the summary would count them as "reviewed with no findings".
        String? failureMessage;
        var attempt = 0;
        while (true) {
          failureMessage = null;
          try {
            results[occurrenceKey] = await _api.review(
              requirementId: item.id,
              text: item.text,
              section: item.section,
              pageIndex: item.pageIndex,
              cancelToken: token,
            );
            break;
          } on ApiException catch (error) {
            // A quota or provider error kills the whole run; a single bad
            // requirement does not. Quota in particular must not be retried —
            // burning three attempts against a 429 makes tomorrow worse, not
            // this run better.
            if (error.statusCode == 429 || error.statusCode == 401) {
              killed = true;
              killMessage = error.message;
              return;
            }
            failureMessage = error.message;
            if (!error.isRetryable ||
                attempt + 1 >= AppConfig.maxReviewAttempts) {
              break;
            }
            attempt++;
            await _backoff(attempt);
            if (token.isCancelled) return;
          } on ContractException catch (error) {
            failureMessage = error.message;
            break;
          } on Object catch (error) {
            // A worker must never die silently and strand the progress bar.
            failureMessage = '$error';
            break;
          }
        }
        if (failureMessage != null) {
          failures[occurrenceKey] = failureMessage;
          failureRequirementIds[occurrenceKey] = item.id;
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

    // The terminal stage is computed once, before the branch that reports it,
    // so the run object and the progress event can never disagree.
    final stage = killed
        ? ReviewStage.failed
        : (cancelled || token.isCancelled
              ? ReviewStage.cancelled
              : ReviewStage.done);
    final run = ReviewRun(
      results: results,
      failures: failures,
      failureRequirementIds: failureRequirementIds,
      stage: stage,
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

  /// Grounded Q&A.
  ///
  /// [context] is the passage set the answer must be drawn from. Callers pass
  /// a bounded slice — the handful of units the offline search surfaced — not
  /// the whole document: a 200-page SRS would blow far past the proxy's
  /// payload limit, and the answer only ever comes from one or two units.
  Future<AskResponse> ask({
    required String question,
    required String context,
  }) => _api.ask(question: question, context: context);
}

/// Exponential backoff between attempts at one requirement: 400ms, 800ms…
///
/// Deliberately short and strictly bounded — retries exist to ride out a brief
/// blip, not to paper over a proxy that is genuinely down. Anything still
/// failing after this is recorded as a failure and the run continues.
Future<void> _backoff(int attempt) => Future<void>.delayed(
  Duration(
    milliseconds:
        AppConfig.reviewRetryBaseDelay.inMilliseconds * (1 << (attempt - 1)),
  ),
);
