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
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../models/diagram_audit.dart';
import '../models/review_models.dart';
import '../models/review_progress.dart';
import '../models/srs_document.dart';
import '../services/api_service.dart';
import '../services/image_budget.dart';
import '../services/page_image_renderer.dart';
import '../services/page_image_selector.dart';
import '../services/review_api.dart';

/// Largest base64 image payload accepted by the review proxy. This is kept in
/// the app layer as a final guard even when a renderer produces valid PNG bytes.
const int kMaxImageB64Characters = 4_000_000;

class ReviewRepository {
  ReviewRepository(this._api, {PageImageRenderer? renderer})
    : _renderer = renderer ?? PageImageRenderer();

  final ReviewApi _api;
  final PageImageRenderer _renderer;
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
  ///
  /// Vision-chain passthroughs: the ViewModel owns the audit flow, the
  /// repository owns the two resources only it holds — the API client and
  /// the PDF renderer. Kept one-liners so no review logic leaks in here.
  Future<DiagramAuditResult> diagramAudit(DiagramAuditRequest request) =>
      _api.diagramAudit(request);

  Future<String> shareReport({
    required String html,
    required String fileName,
  }) => _api.shareReport(html: html, fileName: fileName);

  Future<Uint8List> renderPageForAudit(Uint8List pdfBytes, int pageIndex) =>
      _renderer.renderPage(pdfBytes: pdfBytes, pageIndex: pageIndex);

  /// [pdfBytes] are optional so mock/offline reviews remain text-only. Image
  /// planning and rasterization run only when [imageReviewEnabled] is true;
  /// live imported-PDF callers opt in explicitly. Selected page rasters are
  /// rendered once, cached by page, and reused across retries.
  ///
  /// [figurePages] is the server document map's figure-page list
  /// (`DocumentMap.figurePages`) — the TRUTH about which pages hold drawn
  /// content, including the vector UML no client heuristic can see. When
  /// given, it widens the candidate set; every other step is unchanged.
  Stream<ReviewProgress> run(
    SrsDocument document, {
    required void Function(ReviewRun run) onComplete,
    int concurrency = AppConfig.reviewConcurrency,
    int batchSize = AppConfig.reviewBatchSize,
    // The proxy's real ceiling when `/rubric` supplied one. The compile-time
    // constant is a copy of a server setting, so a deployment that moves it
    // would otherwise be clamped against a number nobody can change.
    int? batchMaxSize,
    Uint8List? pdfBytes,
    bool imageReviewEnabled = false,
    List<int>? figurePages,
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
        batchSize: batchSize.clamp(
          1,
          batchMaxSize ?? AppConfig.reviewBatchMaxSize,
        ),
        pdfBytes: pdfBytes,
        imageReviewEnabled: imageReviewEnabled,
        figurePages: figurePages,
      ),
    );
    return controller.stream;
  }

  Future<void> _drive({
    required SrsDocument document,
    required StreamController<ReviewProgress> controller,
    required void Function(ReviewRun run) onComplete,
    required int concurrency,
    required int batchSize,
    Uint8List? pdfBytes,
    required bool imageReviewEnabled,
    List<int>? figurePages,
  }) async {
    final all = document.requirements;
    final items = all
        .take(AppConfig.maxRequirementsPerRun)
        .toList(growable: false);
    final candidatePages = imageReviewEnabled
        ? {
            ...document.imagePageIndexes,
            // Pages the document's own index says hold a figure. An embedded
            // image is only half the evidence — the OTES diagrams are vector
            // drawings with no image object, so the index is the only way
            // they ever become attachable.
            if (document.blueprint != null)
              for (final figure in document.blueprint!.figures)
                if (figure.isResolved) figure.pdfPageIndex!,
            // Pages the SERVER saw a figure region on. Strongest evidence of
            // the three: measured objects, not a heuristic or a caption.
            ...?figurePages,
          }
        : const <int>{};
    final pageImageSelector = imageReviewEnabled
        ? PageImageSelector(budget: ImageBudget())
        : null;

    // The per-run cap is real, so it is accounted for instead of being
    // applied behind the user's back. `skipped` rides on every progress event
    // and lands in the UI banner.
    final skippedByCap = all.length - items.length;

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

    // Plan in document order before any worker starts. This makes the image
    // budget deterministic and lets us render each selected page exactly once.
    // Image review is opt-in so mock/DOCX/restored runs stay text-only and do
    // not report missing bytes as image failures.
    final plans = <String, PageImagePlan>{};
    final decisionCounts = <String, int>{};
    final reasonCounts = <String, int>{};
    var candidates = 0;
    if (imageReviewEnabled && pageImageSelector != null) {
      for (var index = 0; index < items.length; index++) {
        if (token.isCancelled) {
          break;
        }
        final occurrenceKey = occurrenceKeys[index];
        final plan = pageImageSelector.planFor(
          requirementId: occurrenceKey,
          text: items[index].text,
          pageIndex: items[index].pageIndex,
          candidatePages: candidatePages,
          blueprint: document.blueprint,
          // Lets the selector's thin-image-page fallback judge the page's
          // own extracted text, not just the requirement slice — a diagram
          // section whose pages render as images ("Page | 1 4 Page | 1 5…")
          // has no keyword for the detector to fire on.
          pageText: _pageTextAt(document, items[index].pageIndex),
        );
        plans[occurrenceKey] = plan;
        decisionCounts[plan.decision.name] =
            (decisionCounts[plan.decision.name] ?? 0) + 1;
        if (plan.decision == PageImageDecision.selected ||
            plan.decision == PageImageDecision.deferredBudgetSpent) {
          candidates++;
        }
        if (plan.reason != null) {
          reasonCounts[plan.reason!] = (reasonCounts[plan.reason!] ?? 0) + 1;
        }
      }
    }

    // Render selected pages before the request pool. A page shared by several
    // requirements is rasterized once and its base64 value is reused by every
    // retry. Renderer failures and oversized payloads degrade to text-only.
    final imageB64ByPage = <int, String>{};
    final imageFailureByPage = <int, String>{};
    var extracted = 0;
    var failed = 0;
    if (imageReviewEnabled) {
      for (var index = 0; index < items.length; index++) {
        if (token.isCancelled) {
          break;
        }
        final occurrenceKey = occurrenceKeys[index];
        final plan = plans[occurrenceKey];
        if (plan == null || plan.decision != PageImageDecision.selected) {
          continue;
        }
        final pageIndex = plan.pageIndex!;
        if (imageB64ByPage.containsKey(pageIndex)) {
          extracted++;
          continue;
        }
        if (imageFailureByPage.containsKey(pageIndex)) {
          failed++;
          final reason = imageFailureByPage[pageIndex]!;
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
          continue;
        }
        if (pdfBytes == null || pdfBytes.isEmpty) {
          const reason = 'no-pdf-bytes';
          imageFailureByPage[pageIndex] = reason;
          failed++;
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
          continue;
        }

        try {
          final pngBytes = await _renderer.renderPage(
            pdfBytes: pdfBytes,
            pageIndex: pageIndex,
          );
          if (token.isCancelled) {
            break;
          }
          final imageB64 = base64Encode(pngBytes);
          if (imageB64.length > kMaxImageB64Characters) {
            const reason = 'image-too-large';
            imageFailureByPage[pageIndex] = reason;
            failed++;
            reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
            continue;
          }
          imageB64ByPage[pageIndex] = imageB64;
          extracted++;
        } on Object {
          // A bad/missing page must not kill the whole review. The requirement
          // still gets its ordinary text-only request below. Cancellation wins
          // over attributing a renderer failure to the cancelled run.
          if (token.isCancelled) break;
          const reason = 'render-failed';
          imageFailureByPage[pageIndex] = reason;
          failed++;
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
        }
      }
    }

    final results = <String, ReviewResult>{};
    final failures = <String, String>{};
    final failureRequirementIds = <String, String>{};
    final reviewedOccurrenceKeys = <String>{};
    var next = 0;
    var completed = 0;
    var killed = false;
    var cancelled = false;
    var batchUnsupported = false;
    String? killMessage;

    void emit(ReviewProgress progress) {
      if (!controller.isClosed) controller.add(progress);
    }

    emit(
      ReviewProgress(
        stage: ReviewStage.parsing,
        total: items.length,
        skipped: skippedByCap,
      ),
    );

    /// One unit's page image, when it has one that was actually rendered.
    ///
    /// This is also the batching rule: an image can only ride a single-unit
    /// request, so an image-bearing unit is never packed with its neighbours.
    String? imageFor(int index) {
      final plan = plans[occurrenceKeys[index]];
      return plan != null && plan.decision == PageImageDecision.selected
          ? imageB64ByPage[plan.pageIndex!]
          : null;
    }

    final tasks = planReviewTasks(
      items.length,
      // Two reasons a unit must travel alone: an image can only ride a
      // single-unit request, and the proxy rejects an empty text with a 422 that
      // would otherwise take a whole group down with it.
      travelsAlone: (index) =>
          imageFor(index) != null || items[index].text.trim().isEmpty,
      batchSize: batchSize,
    );

    void recordGroupFailure(List<int> task, String message) {
      // Cancellation wins over attributing a failure to a run the user stopped
      // — the single path guards exactly the same way.
      if (token.isCancelled) return;
      for (final index in task) {
        final occurrenceKey = occurrenceKeys[index];
        failures[occurrenceKey] = message;
        failureRequirementIds[occurrenceKey] = items[index].id;
      }
    }

    /// Reads one `/review/batch` response into [results] and [failures].
    ///
    /// The proxy answers 200 with a `failed` list rather than failing the whole
    /// request, so the units it DID review are kept and only the listed ones are
    /// recorded as failures — throwing the good ones away would mean paying for
    /// them twice on the next attempt.
    void recordGroupOutcome(List<int> task, BatchReviewOutcome outcome) {
      for (var position = 0; position < task.length; position++) {
        final index = task[position];
        final occurrenceKey = occurrenceKeys[index];
        final result = outcome.resultsByIndex[position];
        if (result != null) {
          results[occurrenceKey] = result;
          continue;
        }
        failures[occurrenceKey] =
            outcome.failuresByIndex[position] ??
            'The proxy returned no result for ${items[index].id}.';
        failureRequirementIds[occurrenceKey] = items[index].id;
      }
    }

    /// Reviews a group one unit at a time — the pre-batching call pattern.
    ///
    /// Only reached when the proxy does not know `/review/batch` (404), i.e. an
    /// app that is newer than the deployment it is talking to. Group units never
    /// carry a page image, so this is the plain text path with the same retry
    /// and quota rules as the main single-unit path.
    Future<void> runGroupAsSingles(List<int> task) async {
      for (final index in task) {
        if (killed || token.isCancelled) return;
        final occurrenceKey = occurrenceKeys[index];
        final item = items[index];
        var attempt = 0;

        void record(String message) {
          if (token.isCancelled) return;
          failures[occurrenceKey] = message;
          failureRequirementIds[occurrenceKey] = item.id;
        }

        while (true) {
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
            if (error.statusCode == 429 || error.statusCode == 401) {
              if (token.isCancelled) return;
              killed = true;
              killMessage = error.message;
              return;
            }
            if (!error.isRetryable ||
                attempt + 1 >= AppConfig.maxReviewAttempts) {
              record(error.message);
              break;
            }
            attempt++;
            await _backoff(attempt);
            if (token.isCancelled) return;
          } on ContractException catch (error) {
            record(error.message);
            break;
          } on Object catch (error) {
            record('$error');
            break;
          }
        }
      }
    }

    /// Reviews a group of text-only units in one provider call.
    ///
    /// Same retry policy as the single path: a quota or token rejection kills
    /// the run (retrying a 429 burns tomorrow's quota for tonight's failure), a
    /// transient failure is retried up to [AppConfig.maxReviewAttempts], and a
    /// terminal failure is recorded against every unit in the group.
    Future<void> runGroup(List<int> task) async {
      // A proxy without the endpoint is a deployment skew, not a review
      // failure: drop to one call per unit and keep the run alive.
      if (batchUnsupported) {
        await runGroupAsSingles(task);
        return;
      }
      final units = [
        for (final index in task)
          BatchReviewUnit(
            requirementId: items[index].id,
            text: items[index].text,
            section: items[index].section,
            pageIndex: items[index].pageIndex,
          ),
      ];
      var attempt = 0;
      while (true) {
        try {
          recordGroupOutcome(
            task,
            await _api.reviewBatch(units, cancelToken: token),
          );
          return;
        } on ApiException catch (error) {
          if (error.statusCode == 429 || error.statusCode == 401) {
            if (token.isCancelled) return;
            killed = true;
            killMessage = error.message;
            return;
          }
          if (error.statusCode == 404 || error.statusCode == 413) {
            // 404: a proxy older than this build. 413: a batch it will not
            // carry (fewer units allowed, or a smaller total). Both are
            // properties of the DEPLOYMENT, not of the units, so the run
            // drops to one call per unit and stays alive — and remembers it,
            // because neither answer will change mid-run.
            batchUnsupported = true;
            await runGroupAsSingles(task);
            return;
          }
          if (!error.isRetryable ||
              attempt + 1 >= AppConfig.maxReviewAttempts) {
            recordGroupFailure(task, error.message);
            return;
          }
          attempt++;
          await _backoff(attempt);
          if (token.isCancelled) return;
        } on ContractException catch (error) {
          recordGroupFailure(task, error.message);
          return;
        } on Object catch (error) {
          recordGroupFailure(task, '$error');
          return;
        }
      }
    }

    Future<void> worker() async {
      while (true) {
        if (killed || token.isCancelled) {
          cancelled = token.isCancelled;
          return;
        }
        final taskIndex = next++;
        if (taskIndex >= tasks.length) return;
        final task = tasks[taskIndex];
        final index = task.first;
        final occurrenceKey = occurrenceKeys[index];
        final item = items[index];
        final imageB64 = task.length == 1 ? imageFor(index) : null;

        emit(
          ReviewProgress(
            stage: ReviewStage.reviewing,
            completed: completed,
            total: items.length,
            currentRequirementId: item.id,
            skipped: skippedByCap,
          ),
        );

        if (task.length > 1) {
          await runGroup(task);
          if (killed || token.isCancelled) {
            cancelled = token.isCancelled;
            return;
          }
          completed += task.length;
          emit(
            ReviewProgress(
              stage: ReviewStage.reviewing,
              completed: completed,
              total: items.length,
              skipped: skippedByCap,
            ),
          );
          continue;
        }

        // Retry only what is worth retrying. `isRetryable` has been set on
        // ApiException since day one but nothing ever read it, so a dropped
        // connection or a 90s timeout cost a requirement outright and the run
        // marched on — a whole document could lose units to a brief blip and
        // the summary would count them as "reviewed with no findings".
        final bool hasImage = imageB64 != null;
        String? imageFailureMessage;
        var imageRequestFailed = false;
        var attempt = 0;

        void recordImageFailure() {
          if (hasImage && !token.isCancelled) {
            failed++;
            reasonCounts['image-request-failed'] =
                (reasonCounts['image-request-failed'] ?? 0) + 1;
          }
        }

        // Exhaust the image-bearing attempt first. A transient failure that
        // later succeeds is not an image failure; only a terminal image error
        // is eligible for the one text-only fallback below.
        while (true) {
          imageFailureMessage = null;
          try {
            results[occurrenceKey] = await _api.review(
              requirementId: item.id,
              text: item.text,
              section: item.section,
              pageIndex: item.pageIndex,
              imageB64: imageB64,
              cancelToken: token,
            );
            if (hasImage) {
              reviewedOccurrenceKeys.add(occurrenceKey);
            }
            break;
          } on ApiException catch (error) {
            // A quota or provider error kills the whole run; a single bad
            // requirement does not. Quota in particular must not be retried —
            // burning three attempts against a 429 makes tomorrow worse, not
            // this run better.
            if (error.statusCode == 429 || error.statusCode == 401) {
              if (token.isCancelled) return;
              recordImageFailure();
              killed = true;
              killMessage = error.message;
              return;
            }
            imageFailureMessage = error.message;
            if (!error.isRetryable ||
                attempt + 1 >= AppConfig.maxReviewAttempts) {
              recordImageFailure();
              imageRequestFailed = true;
              break;
            }
            attempt++;
            await _backoff(attempt);
            if (token.isCancelled) return;
          } on ContractException catch (error) {
            imageFailureMessage = error.message;
            recordImageFailure();
            imageRequestFailed = true;
            break;
          } on Object catch (error) {
            // A worker must never die silently and strand the progress bar.
            imageFailureMessage = '$error';
            recordImageFailure();
            imageRequestFailed = true;
            break;
          }
        }

        String? failureMessage = imageFailureMessage;
        if (imageRequestFailed) {
          if (token.isCancelled) return;
          if (hasImage) {
            // Preserve the unit when the vision path is unavailable: retry the
            // same requirement once without the optional image payload.
            try {
              results[occurrenceKey] = await _api.review(
                requirementId: item.id,
                text: item.text,
                section: item.section,
                pageIndex: item.pageIndex,
                cancelToken: token,
              );
              failureMessage = null;
            } on ApiException catch (error) {
              if (token.isCancelled) return;
              if (error.statusCode == 429 || error.statusCode == 401) {
                killed = true;
                killMessage = error.message;
                return;
              }
              failureMessage = error.message;
            } on ContractException catch (error) {
              if (token.isCancelled) return;
              failureMessage = error.message;
            } on Object catch (error) {
              if (token.isCancelled) return;
              failureMessage = '$error';
            }
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
            skipped: skippedByCap,
          ),
        );
      }
    }

    // One worker per task: a task is now either a single image-bearing unit or
    // a group of text-only ones, so the pool size bounds in-flight provider
    // calls, which is what the quota actually cares about.
    final pool = [
      for (var i = 0; i < concurrency && i < tasks.length; i++) worker(),
    ];
    await Future.wait(pool);
    cancelled = cancelled || token.isCancelled;

    // The terminal stage is computed once, before the branch that reports it,
    // so the run object and the progress event can never disagree.
    final stage = killed
        ? ReviewStage.failed
        : (cancelled ? ReviewStage.cancelled : ReviewStage.done);
    final reviewed = reviewedOccurrenceKeys.length;
    final run = ReviewRun(
      results: results,
      failures: failures,
      failureRequirementIds: failureRequirementIds,
      stage: stage,
      skipped: skippedByCap,
      imageCoverage: PageImageCoverage(
        candidates: candidates,
        extracted: extracted,
        reviewed: reviewed,
        skipped: items.length - reviewed,
        failed: failed,
        reasons: reasonCounts,
        decisions: decisionCounts,
        reviewedOccurrenceKeys: reviewedOccurrenceKeys,
      ),
    );
    _cancelToken = null;

    if (killed) {
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.failed,
          completed: results.length,
          total: items.length,
          skipped: skippedByCap,
          error: killMessage,
        ),
      );
    } else if (cancelled) {
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.cancelled,
          completed: results.length,
          total: items.length,
          skipped: skippedByCap,
        ),
      );
    } else {
      emit(
        ReviewProgress(
          stage: ReviewStage.verifying,
          completed: results.length,
          total: items.length,
          skipped: skippedByCap,
        ),
      );
      onComplete(run);
      emit(
        ReviewProgress(
          stage: ReviewStage.done,
          completed: results.length,
          total: items.length,
          skipped: skippedByCap,
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

/// Safe lookup of a page's extracted text for the image planner. Out-of-range
/// and null indexes yield null, in which case the selector falls back to the
/// requirement's own text.
String? _pageTextAt(SrsDocument document, int? pageIndex) {
  if (pageIndex == null ||
      pageIndex < 0 ||
      pageIndex >= document.pageTexts.length) {
    return null;
  }
  return document.pageTexts[pageIndex];
}

/// Groups unit indices into the work items one worker picks up at a time.
///
/// A unit that [travelsAlone] (a page raster is attached, or its text is empty)
/// is never packed: `/review/batch` is a text call, and one request carrying
/// several page images would be several MB.
/// Everything else is packed up to [batchSize], which is what turns a 130-unit
/// document from 130 provider calls into ~22 — the measured OTES run spent 1109
/// of its 1347 upstream calls being refused, and most of that load was simply
/// one call per unit in parallel.
///
/// Order is preserved (groups are contiguous runs of the document), so progress
/// still moves through the document rather than jumping around.
List<List<int>> planReviewTasks(
  int count, {
  required bool Function(int index) travelsAlone,
  required int batchSize,
}) {
  final tasks = <List<int>>[];
  var pending = <int>[];
  void flush() {
    if (pending.isEmpty) return;
    tasks.add(pending);
    pending = <int>[];
  }

  for (var index = 0; index < count; index++) {
    if (batchSize <= 1 || travelsAlone(index)) {
      flush();
      tasks.add([index]);
      continue;
    }
    pending.add(index);
    if (pending.length >= batchSize) flush();
  }
  flush();
  return tasks;
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
