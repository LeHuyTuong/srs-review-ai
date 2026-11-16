/// One review run and its diagram audit: start, stream progress, cancel,
/// triage findings, verify quotes, render a page for the vision pass, and save
/// the finished run.
///
/// The only place that talks to `ReviewRepository` and `VisionReviewService`.
/// The session-transient handles it shares with the other controllers
/// (`_document`, `_pdfBytes`, `_documentMap`, `_uploadUri`) come from
/// [WorkspaceController].
part of '../workspace_view_model.dart';

final class ReviewRunController extends WorkspaceController {
  ReviewRunController(super.vm);

  StreamSubscription<ReviewProgress>? _subscription;

  Timer? _elapsedTimer;

  /// Ticks once a second while a review runs so the progress surface can show
  /// a live elapsed time. Without it a long run looks identical to a hang —
  /// the exact complaint this fixes.
  void _startElapsedTicker() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isRunning) {
        // Re-emit for the clock; progress itself is untouched.
        state = state.copyWith(progress: state.progress);
      } else {
        _elapsedTimer?.cancel();
        _elapsedTimer = null;
      }
    });
  }

  /// Records what the student decided about one finding.
  ///
  /// `open` is stored as "absent" so saved sessions stay a valid key set — an
  /// unseen id simply reads back as open.
  void setFindingStatus(String findingId, FindingStatus status) {
    final next = Map<String, FindingStatus>.from(state.findingStatus);
    if (status == FindingStatus.open) {
      next.remove(findingId);
    } else {
      next[findingId] = status;
    }
    state = state.copyWith(findingStatus: next);
  }

  /// Round 9 — runs the [Verifier] against the current deterministic
  /// findings and writes the resulting status map back to state.
  ///
  /// A future "Re-verify" button (or a re-import flow that re-parses
  /// the same bytes) calls this. Right now the only caller is the
  /// Verifier self-test; the API exists so the re-run UI in R10+ does
  /// not have to reach into the data layer.
  ///
  /// Returns a [VerifyDiff] describing what changed, so the caller can
  /// surface a meaningful toast ("X promoted to verified, Y
  /// reopened"). No-op when the current parse and the previous
  /// statuses already agree — the state is not touched and the
  /// returned diff is empty.
  VerifyDiff verifyStatuses() {
    final previous = state.findingStatus;
    const verifier = Verifier();
    final next = verifier.verify(
      previousStatuses: previous,
      syllabusFindings: state.syllabusFindings,
      referenceFindings: state.referenceFindings,
      blueprintFindings: state.blueprintFindings,
    );
    if (_statusMapEquals(next, previous)) {
      return const VerifyDiff();
    }
    state = state.copyWith(findingStatus: next);
    return VerifyDiff.compute(before: previous, after: next);
  }

  static bool _statusMapEquals(
    Map<String, FindingStatus> a,
    Map<String, FindingStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> runReview() async {
    if (state.isRunning) return;
    final selected = state.units.where((u) => u.selected).toList();
    if (selected.isEmpty) {
      state = state.copyWith(
        error:
            'No units selected. Adjust your selection; nothing will be '
            'silently skipped.',
      );
      return;
    }
    // The per-run cap is applied as a CLAMP by the repository, never as a
    // refusal.
    //
    // Refusing here was worse than useless: the demo selects 63 of 65 units
    // against a 40-unit cap, so pressing "Review 63 units" closed the sheet,
    // aborted, and wrote the error into the sheet that had just been
    // destroyed. The user saw a frozen screen with no reason for it
    // (docs/uiux/audit-2026-09-11.md P0-2, P0-4). We now review as much as the
    // cap allows and state the shortfall in the progress bar and the summary.
    final capped = selected.take(AppConfig.maxRequirementsPerRun).toList();
    final document = _document;
    if (document == null) {
      state = state.copyWith(
        error:
            'Restored sessions hold no file bytes. Import a document before '
            'running a new review.',
      );
      return;
    }

    // Match by inventory occurrence, not raw id: real SRS files may reuse an
    // id for several distinct tables. An id-indexed map silently drops those
    // occurrences before they ever reach the review repository.
    final unitIndexByKey = <String, int>{
      for (var index = 0; index < state.units.length; index++)
        state.units[index].key: index,
    };
    final selectedItems = <RequirementItem>[];
    final selectedOccurrenceKeys = <String>[];
    for (final unit in capped) {
      final index = unitIndexByKey[unit.key];
      if (index == null || index >= document.requirements.length) continue;
      selectedItems.add(document.requirements[index]);
      selectedOccurrenceKeys.add(unit.key);
    }
    final filtered = SrsDocument(
      fileName: state.fileName,
      pageCount: document.pageCount,
      pageTexts: document.pageTexts,
      requirements: selectedItems,
      occurrenceKeys: selectedOccurrenceKeys,
      imagePageIndexes: document.imagePageIndexes,
    );

    final imageReviewEnabled =
        state.imageReviewAvailable &&
        !ref.read(mockModeProvider) &&
        _pdfBytes != null;

    state = state.copyWith(
      clearError: true,
      clearResult: true,
      runStartedAt: DateTime.now(),
      runReviewed: 0,
      // Hide the previous run's summary for the duration of the new one; the
      // finished run re-opens it.
      runSummaryDismissed: true,
      imageReviewedCount: 0,
      clearImageCoverage: true,
      runSkipped: selected.length - selectedItems.length,
      progress: ReviewProgress(
        stage: ReviewStage.parsing,
        total: selectedItems.length,
        // Units the user selected that this run cannot cover. The progress
        // bar says so in plain words instead of letting the run look complete.
        skipped: selected.length - selectedItems.length,
      ),
    );
    _startElapsedTicker();
    _log('Khởi tạo lượt chấm cho ${selectedItems.length} yêu cầu đã chọn');
    _log(
      'Chế độ: ${ref.read(mockModeProvider) ? "Mô phỏng ngoại tuyến (Offline Mock)" : "Trực tuyến (LLM Proxy)"}',
    );
    if (imageReviewEnabled) {
      _log(
        'Kích hoạt Multimodal Vision cho ${_documentMap?.figurePages.length ?? 0} trang sơ đồ',
      );
    }

    // One read, both uses: the version goes into the result, and the batch
    // ceiling replaces the client's compile-time copy of a server setting when
    // the proxy published one.
    final rubric = ref.read(rubricProvider).value;
    final rubricVersion = rubric?.version ?? RubricConfig.fallback.version;
    final repository = ref.read(reviewRepositoryProvider);

    await _subscription?.cancel();
    _subscription = repository
        .run(
          filtered,
          pdfBytes: imageReviewEnabled ? _pdfBytes : null,
          imageReviewEnabled: imageReviewEnabled,
          // The server's figure pages (truth) when the anatomy pass ran; null
          // keeps the heuristic candidate set exactly as it was.
          figurePages: _documentMap?.figurePages,
          batchMaxSize: rubric?.maxBatchUnits,
          onComplete: (run) {
            final result = WorkspaceReviewResult.fromRun(
              run: run,
              document: filtered,
              units: state.units,
              rubricVersion: rubricVersion,
              currentMode: ref.read(mockModeProvider),
            );
            // A unit is "reviewed" ONLY if the run actually returned a result
            // for its id. Being selected proves intent, not work: a run killed
            // by a 429 or cancelled at the first unit must not stamp "reviewed"
            // onto 50 rows while coverage honestly says zero. Selected units the
            // run never reached go back to pending; per-unit failures land in
            // failed; units left out of the selection stay skipped.
            state = state.copyWith(
              result: result,
              imageReviewedCount: imageReviewEnabled
                  ? run.imageCoverage.reviewed
                  : 0,
              imageCoverage: imageReviewEnabled ? run.imageCoverage : null,
              units: [
                for (final unit in state.units)
                  unit.copyWith(
                    status: run.results.containsKey(unit.key)
                        ? UnitStatus.reviewed
                        : run.failures.containsKey(unit.key)
                        ? UnitStatus.failed
                        : unit.selected
                        ? UnitStatus.pending
                        : UnitStatus.skipped,
                  ),
              ],
            );
            _log('Hoàn tất chấm ${run.results.length} yêu cầu');
            if (result.totalTokens > 0) {
              _log(
                'AI token usage: ${result.totalTokens} tokens (${result.promptTokens} prompt · ${result.completionTokens} candidates)',
              );
            }
            if (run.totalDropped > 0) {
              _log(
                'Loại bỏ ${run.totalDropped} lỗi do không khớp trích dẫn nguyên văn',
              );
            }
            _log(
              'Tính điểm hoàn tất: ${result.findings.length} lỗi phát hiện trên ${result.reviewed} yêu cầu',
            );
          },
        )
        .listen(
          (progress) async {
            // The repository reports what it dropped from the document it was
            // handed — always 0 here, because the view model already clamped the
            // selection. The user-facing shortfall is THIS layer's number, so it
            // is re-attached to every progress event rather than being overwritten
            // and making the warning flicker out of existence.
            state = state.copyWith(
              progress: ReviewProgress(
                stage: progress.stage,
                completed: progress.completed,
                total: progress.total,
                currentRequirementId: progress.currentRequirementId,
                error: progress.error,
                skipped: state.runSkipped,
              ),
            );
            if (progress.stage == ReviewStage.parsing) {
              _log('Đang phân tách và chuẩn hóa ngữ cảnh các yêu cầu...');
            } else if (progress.stage == ReviewStage.reviewing &&
                progress.currentRequirementId != null) {
              _log(
                'Đang chấm điểm AI: ${progress.completed}/${progress.total} (${progress.currentRequirementId})',
              );
            } else if (progress.stage == ReviewStage.verifying) {
              _log(
                'Đang kiểm tra trích dẫn nguyên văn (Exact Verbatim Verification)...',
              );
            }
            if (progress.stage == ReviewStage.done ||
                progress.stage == ReviewStage.cancelled ||
                progress.stage == ReviewStage.failed) {
              await _onRunFinished(progress);
            }
          },
          onError: (Object error) {
            // The stream's own error text, not a generic sentence. A run that
            // died on a refused connection used to report "Review failed." and
            // nothing else, so the user had no way to tell a dead server from
            // a spent quota from a bad file.
            state = state.copyWith(
              clearProgress: true,
              error:
                  'Chấm điểm thất bại: $error. Danh sách chọn của bạn '
                  'được giữ nguyên.',
            );
          },
        );
  }

  Future<void> _onRunFinished(ReviewProgress progress) async {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    // `runSkipped` is deliberately NOT overwritten from the progress event:
    // the repository reports what it dropped from the document it received,
    // which is 0 because the view model already clamped. Only the view model
    // knows how many SELECTED units fell outside the run.
    final skipped = state.runSkipped;
    final result = state.result;

    // A cancelled or quota-killed run still produced real, paid-for results.
    // Saving only once a run reached `done` meant a 429 at unit 39 of 40 threw
    // away 38 reviewed units: the quota was spent and nothing was kept, so the
    // only recovery was to run — and pay for — the whole thing again.
    var saved = false;
    if (result != null &&
        (progress.stage == ReviewStage.done || result.reviewed > 0)) {
      saved = await _saveSession(result);
    }

    if (progress.stage == ReviewStage.done) {
      final reviewed = result?.reviewed ?? 0;
      final findings = result?.findings.length ?? 0;
      final failed = result?.failed ?? 0;
      // "Done" with nothing reviewed is not a clean run — it is a run where
      // every request was refused, and the only honest thing to show is an
      // error the user cannot miss. Reporting it as a success toast is what
      // made a 100%-failed run look like the document had no issues at all.
      if (reviewed == 0 && progress.total > 0) {
        state = state.copyWith(
          clearProgress: true,
          runStartedAt: DateTime.now(),
          runReviewed: 0,
          runSkipped: skipped,
          error:
              'Không mục nào được chấm (${progress.total} mục đã chọn). '
              'Máy chủ chấm điểm từ chối hoặc mất kết nối — kiểm tra máy chủ '
              'và lượt chấm trong ngày rồi thử lại. Danh sách chọn được giữ '
              'nguyên.',
        );
        return;
      }
      // "0 units reviewed · 0 findings" is indistinguishable from a clean run
      // with nothing to report. If units failed — a dead proxy, a bad payload
      // — say so, or the user draws exactly the wrong conclusion from it.
      final failNote = failed > 0
          ? ' · $failed failed and were NOT reviewed'
          : '';
      // If the per-run cap bit, say so rather than letting the user believe
      // the whole document was covered — this app's entire pitch is that it
      // never truncates silently.
      final capNote = skipped > 0
          ? ' · $skipped left out by the ${AppConfig.maxRequirementsPerRun}-unit per-run cap'
          : '';
      // A run whose pages could not be rendered is not a text-only run by
      // choice: say so, or the diagram findings read as if the pictures had
      // been graded.
      final rendererNote = state.diagramsWereTextOnly ? kNoPdfRendererNote : '';
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: reviewed,
        runSkipped: skipped,
        // The run ended here, so the shell's summary bar takes over from the
        // progress bar: same slot, same visibility, but now with the two
        // actions a finished run implies instead of a Cancel button.
        runSummaryDismissed: false,
        toast:
            '$reviewed units reviewed · $findings verified findings'
            '$failNote$capNote$rendererNote'
            '${saved ? ' · saved on this device' : ''}',
      );
    } else if (progress.stage == ReviewStage.cancelled) {
      final kept = result?.reviewed ?? progress.completed;
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: kept,
        runSkipped: skipped,
        toast: kept > 0
            ? 'Review cancelled · $kept unit(s) reviewed'
                  '${saved ? ' and saved on this device' : ''}.'
            : 'Review cancelled · nothing had been reviewed yet.',
      );
    } else {
      final kept = result?.reviewed ?? progress.completed;
      final keptNote = kept > 0
          ? ' $kept unit(s) were reviewed'
                '${saved ? ' and saved on this device' : ''}.'
          : '';
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: kept,
        runSkipped: skipped,
        error:
            '${progress.error ?? 'Review failed.'} Your selection is '
            'preserved.$keptNote',
      );
    }
    _scheduleToastClear();
  }

  void cancelReview() {
    ref.read(reviewRepositoryProvider).cancel();
  }

  /// Closes the "run finished" summary bar. Same lifetime as a toast except
  /// this one waits for the user instead of a timer: the two buttons in it
  /// ("View findings", "Export") are the actions a finished run implies.
  void dismissRunSummary() {
    state = state.copyWith(runSummaryDismissed: true);
  }

  /// Closes the error banner.
  ///
  /// The only way [WorkspaceState.error] stops being shown. Nothing clears it
  /// on a timer: an error that vanishes after a few seconds cannot be read,
  /// copied or acted on, and a failed AI run has no other trace — the units
  /// just sit there marked failed with no reason attached.
  void dismissError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}
