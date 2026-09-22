/// ViewModel for the workspace — the Flutter port of the brief's `Workspace`
/// component state, minus anything that renders.
///
/// Holds the inventory (units), the loaded document, the latest review result,
/// review progress, history and toasts. Views read state and call commands;
/// filters and pagination stay as local widget state, exactly like the brief
/// keeps them in the component layer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../../core/providers.dart';
import '../../../data/checks/blueprint_checks.dart';
import '../../../data/checks/reference_checks.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/checks/syllabus_checks.dart';
import '../../../data/checks/verifier.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/review_progress.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/services/report_exporter.dart';
import '../../../data/services/session_store.dart';
import '../../../data/services/vision_review_service.dart';

import '../models/ask_document.dart';
import '../models/demo_units.dart';
import '../models/html_report.dart';
import '../models/report_export.dart';
import '../models/workspace_findings.dart';
import '../models/workspace_unit.dart';

/// Views need the SavedSession shape to render history rows; they reach it
/// through the ViewModel layer, never by importing data/services directly.
export '../../../data/services/session_store.dart' show SavedSession;

/// The ids the demo keeps visible as unclassified, mirroring the brief's
/// two malformed synthetic ids.
const Set<String> _demoMalformedIds = {'UC0134', 'UC0114'};

class WorkspaceState {
  const WorkspaceState({
    this.hasDocument = false,
    this.fileName = '',
    this.pageCount = 0,
    this.sizeLabel = '',
    this.isDemo = false,
    this.units = const [],
    this.syllabusFindings = const [],
    this.referenceFindings = const [],
    this.blueprintFindings = const [],
    this.result,
    this.progress,
    this.error,
    this.toast = '',
    this.importStatus,
    this.history = const [],
    this.historyLoading = false,
    this.restoring = true,
    this.runStartedAt,
    this.runReviewed = 0,
    this.runSkipped = 0,
    this.findingStatus = const {},
    this.diagramPageCount = 0,
    this.isAuditingDiagrams = false,
    this.isSharingReport = false,
    this.imageReviewAvailable = false,
    this.imageReviewedCount = 0,
    this.imageCoverage,
    this.documentFingerprint = '',
    this.parserVersion = '',
    this.runSummaryDismissed = false,
  });

  final bool hasDocument;
  final String fileName;
  final int pageCount;
  final String sizeLabel;
  final bool isDemo;
  final List<WorkspaceUnit> units;
  final List<DeterministicFinding> syllabusFindings;

  /// M2 reference-check results — `reference_checks.dart`. Same lifecycle
  /// as [syllabusFindings] (computed once at load time) but visually rendered
  /// under their own heading so the findings tab separates "syllabus
  /// failures" from "consistency smells". A future round will move these
  /// out into the per-tile dashboard; for now they travel next to the F7/F8/F9
  /// data so the ViewModel is the only place that needs new wiring when that
  /// happens.
  final List<DeterministicFinding> referenceFindings;

  /// Document-index (blueprint) findings — computed once at load time like the
  /// families above, rendered under their own "Mục lục" heading because their
  /// fix lives in the table of contents, not in a requirement sentence.
  final List<DeterministicFinding> blueprintFindings;
  final WorkspaceReviewResult? result;

  /// Non-null while a review is running or has just finished.
  final ReviewProgress? progress;
  final String? error;
  final String toast;

  /// Non-null while an import (pick -> parse -> checks) is in flight; carries
  /// the human-readable phase so the empty state can show real progress for
  /// large files instead of a silent gap.
  final String? importStatus;
  final List<SavedSession> history;
  final bool historyLoading;

  /// True until the persisted snapshot has been restored (or found absent).
  final bool restoring;

  /// When the current (or most recent) review started, so the progress surface
  /// can show elapsed time.
  final DateTime? runStartedAt;

  /// Units actually reviewed by the last finished run.
  final int runReviewed;

  /// Units the per-run cap left out of the last run. Non-zero means the button
  /// promised more work than was done, and the UI says so out loud.
  final int runSkipped;

  /// Triage state per finding id.
  ///
  /// Findings used to be read-only text with nowhere to record a decision, so
  /// the app could never answer "what did I fix since last time?" — which is
  /// the only question a pre-submission checker is really for.
  final Map<String, FindingStatus> findingStatus;

  /// Pages that look like a diagram.
  ///
  /// Zero means "none detected", never "all checked". Image review is tracked
  /// separately because only a current imported PDF can supply page bytes.
  final int diagramPageCount;

  /// True while the vision audit runs. Deliberately its own flag, not a
  /// [ReviewProgress] stage: the audit's unit of work is a page-request,
  /// not a requirement-unit, and pretending otherwise would draw a
  /// progress bar that means something different mid-run.
  final bool isAuditingDiagrams;

  /// In-flight flag for the share-by-link POST (plan 6).
  final bool isSharingReport;

  /// True only while original bytes from a newly imported PDF are retained in
  /// memory. DOCX, demo, and restored sessions are always text-only here.
  final bool imageReviewAvailable;

  /// Requirements in the latest run whose successful request carried a PDF
  /// page image. This is not persisted with snapshots or saved sessions.
  final int imageReviewedCount;

  /// Round 10 — derived run mode (goal §0 degraded-mode-first).
  ///
  /// Decides which goal §2 stages the current run can exercise:
  ///   - full:        text AND vision pass reachable AND diagrams exist
  ///   - textFirst:   text extracted; vision not reachable OR no diagrams
  ///   - blind:       parsed but no text — PDF scanned, OCR / vision only
  ///
  /// Pure derivation over [units] / [imageReviewAvailable] /
  /// [diagramPageCount]; nothing is stored, so the badge never drifts
  /// from the inputs. The decision rule itself lives in
  /// [ReviewMode.decide] so it can be unit-tested without the full
  /// state scaffolding.
  ReviewMode get currentMode => ReviewMode.decide(
    unitsEmpty: units.isEmpty,
    visionReady: imageReviewAvailable,
    hasDiagrams: diagramPageCount > 0,
  );

  /// Full page-image selection, extraction, and request coverage for the latest
  /// run. This is transient UI/report context and is never serialized.
  final PageImageCoverage? imageCoverage;

  /// Identity of the reviewed content: the document fingerprint and the
  /// parser version that produced it. Snapshots and sessions record both so a
  /// restore can refuse to reuse review results across parser changes.
  /// '' while no document is loaded.
  final String documentFingerprint;

  /// Version of the parser that produced [units]; see [kParserVersion].
  final String parserVersion;

  /// Findings the student has marked as worth acting on.
  int get fixedCount =>
      findingStatus.values.where((s) => s == FindingStatus.fixed).length;

  FindingStatus statusOf(String findingId) =>
      findingStatus[findingId] ?? FindingStatus.open;

  Duration? get runElapsed {
    final start = runStartedAt;
    if (start == null || !isRunning) return null;
    return DateTime.now().difference(start);
  }

  bool get isRunning =>
      progress != null && _runningStages.contains(progress!.stage);
  bool get hasResult => result != null;

  /// True once the user has closed the "run finished" summary bar.
  ///
  /// The bar is the only place in the shell that survives after a run ends —
  /// without it, a finished run left the user on the same page they started
  /// on, with the findings one tab away and nothing pointing at them.
  final bool runSummaryDismissed;

  /// Whether the shell should render the "run finished · N reviewed" bar.
  ///
  /// Gated on [runReviewed] > 0 rather than [hasResult]: `result` is persisted
  /// in snapshots, so a `hasResult` gate would re-open the app onto a summary
  /// of a run from a previous session. `runReviewed` only ever describes the
  /// run that just finished in this session.
  bool get showsRunSummary =>
      !isRunning && !runSummaryDismissed && hasResult && runReviewed > 0;

  int get selectedCount => units.where((u) => u.selected).length;
  int get attentionCount => units.where((u) => u.malformed).length;
  int get useCaseCount => units.where((u) => u.kind == UnitKind.useCase).length;
  int get otherRequirementsCount => units
      .where(
        (u) =>
            u.kind == UnitKind.businessRule ||
            u.kind == UnitKind.nonFunctional ||
            u.kind == UnitKind.functional ||
            u.kind == UnitKind.section,
      )
      .length;

  static const Set<ReviewStage> _runningStages = {
    ReviewStage.parsing,
    ReviewStage.reviewing,
    ReviewStage.verifying,
  };

  WorkspaceState copyWith({
    bool? hasDocument,
    String? fileName,
    int? pageCount,
    String? sizeLabel,
    bool? isDemo,
    List<WorkspaceUnit>? units,
    List<DeterministicFinding>? syllabusFindings,
    List<DeterministicFinding>? referenceFindings,
    List<DeterministicFinding>? blueprintFindings,
    WorkspaceReviewResult? result,
    bool clearResult = false,
    ReviewProgress? progress,
    bool clearProgress = false,
    String? error,
    bool clearError = false,
    String? toast,
    bool clearToast = false,
    String? importStatus,
    bool clearImportStatus = false,
    List<SavedSession>? history,
    bool? historyLoading,
    bool? restoring,
    DateTime? runStartedAt,
    bool clearRunStartedAt = false,
    int? runReviewed,
    int? runSkipped,
    Map<String, FindingStatus>? findingStatus,
    int? diagramPageCount,
    bool? isAuditingDiagrams,
    bool? isSharingReport,
    bool? imageReviewAvailable,
    int? imageReviewedCount,
    PageImageCoverage? imageCoverage,
    bool clearImageCoverage = false,
    String? documentFingerprint,
    String? parserVersion,
    bool? runSummaryDismissed,
  }) => WorkspaceState(
    hasDocument: hasDocument ?? this.hasDocument,
    fileName: fileName ?? this.fileName,
    pageCount: pageCount ?? this.pageCount,
    sizeLabel: sizeLabel ?? this.sizeLabel,
    isDemo: isDemo ?? this.isDemo,
    units: units ?? this.units,
    syllabusFindings: syllabusFindings ?? this.syllabusFindings,
    referenceFindings: referenceFindings ?? this.referenceFindings,
    blueprintFindings: blueprintFindings ?? this.blueprintFindings,
    result: clearResult ? null : (result ?? this.result),
    progress: clearProgress ? null : (progress ?? this.progress),
    error: clearError ? null : (error ?? this.error),
    toast: clearToast ? '' : (toast ?? this.toast),
    importStatus: clearImportStatus
        ? null
        : (importStatus ?? this.importStatus),
    history: history ?? this.history,
    historyLoading: historyLoading ?? this.historyLoading,
    restoring: restoring ?? this.restoring,
    runStartedAt: clearRunStartedAt
        ? null
        : (runStartedAt ?? this.runStartedAt),
    runReviewed: runReviewed ?? this.runReviewed,
    runSkipped: runSkipped ?? this.runSkipped,
    findingStatus: findingStatus ?? this.findingStatus,
    diagramPageCount: diagramPageCount ?? this.diagramPageCount,
    isAuditingDiagrams: isAuditingDiagrams ?? this.isAuditingDiagrams,
    isSharingReport: isSharingReport ?? this.isSharingReport,
    imageReviewAvailable: imageReviewAvailable ?? this.imageReviewAvailable,
    imageReviewedCount: imageReviewedCount ?? this.imageReviewedCount,
    imageCoverage: clearImageCoverage
        ? null
        : (imageCoverage ?? this.imageCoverage),
    documentFingerprint: documentFingerprint ?? this.documentFingerprint,
    parserVersion: parserVersion ?? this.parserVersion,
    runSummaryDismissed: runSummaryDismissed ?? this.runSummaryDismissed,
  );
}

class WorkspaceViewModel extends Notifier<WorkspaceState> {
  /// Stateless and platform-delegating, so it needs no provider: constructing
  /// it inline keeps the ViewModel constructible in tests that only care about
  /// review behaviour.
  static const ReportExporter _exporter = ReportExporter();

  SrsDocument? _document;
  Uint8List? _pdfBytes;
  StreamSubscription<ReviewProgress>? _subscription;
  Timer? _toastTimer;
  Timer? _elapsedTimer;
  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _toastTimer?.cancel();
      _elapsedTimer?.cancel();
    });
    scheduleMicrotask(_restoreSnapshot);
    return const WorkspaceState();
  }

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

  // ------------------------------------------------------------- demo / import

  Future<void> loadDemo() async {
    if (state.isRunning) return;
    final document = demoDocument();
    // Units are immutable: flagged ones are REPLACED, never edited in place.
    final units = [
      for (final unit in unitsFromDocument(document))
        if (_demoMalformedIds.contains(unit.id))
          unit.classified(UnitKind.unknown)
        else
          unit,
    ];
    _document = document;
    _pdfBytes = null;
    state = WorkspaceState(
      hasDocument: true,
      fileName: demoFileName,
      pageCount: demoPageCount,
      sizeLabel: '27.37 MB',
      isDemo: true,
      units: units,
      syllabusFindings: SyllabusChecks(RubricConfig.fallback).runAll(document),
      referenceFindings: const ReferenceChecks().runAll(document),
      blueprintFindings: const BlueprintChecks().runAll(document.blueprint),
      diagramPageCount: document.imagePageIndexes.length,
      imageReviewAvailable: false,
      imageReviewedCount: 0,
      imageCoverage: null,
      documentFingerprint: document.documentFingerprint,
      parserVersion: kParserVersion,
      toast:
          '${units.length} units extracted. All detected IDs have been preserved.',
    ).copyWith(restoring: false);
    _scheduleToastClear();
    await _saveSnapshot();
  }

  Future<void> importDocument() async {
    if (state.isRunning) return;
    state = state.copyWith(
      clearError: true,
      historyLoading: false,
      importStatus: 'Reading file…',
    );
    final repository = ref.read(documentRepositoryProvider);
    try {
      final loaded = await repository.pickAndParse(
        onStatus: (status) => state = state.copyWith(importStatus: status),
      );
      if (loaded == null) {
        // user cancelled the picker; keep the current document and bytes
        state = state.copyWith(clearImportStatus: true);
        return;
      }
      _document = loaded.document;
      _pdfBytes = loaded.pdfBytes;
      state = WorkspaceState(
        hasDocument: true,
        fileName: loaded.document.fileName,
        pageCount: loaded.document.pageCount,
        sizeLabel: _formatBytes(loaded.sizeBytes),
        isDemo: false,
        units: unitsFromDocument(loaded.document),
        syllabusFindings: loaded.findings,
        referenceFindings: loaded.referenceFindings,
        blueprintFindings: loaded.blueprintFindings,
        // How many pages look like diagrams. Recorded at import so the report
        // can distinguish diagram detection from actual image review.
        diagramPageCount: loaded.document.imagePageIndexes.length,
        imageReviewAvailable: loaded.pdfBytes != null,
        imageReviewedCount: 0,
        imageCoverage: null,
        documentFingerprint: loaded.document.documentFingerprint,
        parserVersion: kParserVersion,
        toast:
            '${loaded.document.requirements.length} units extracted. '
            'All detected IDs have been preserved.',
      ).copyWith(restoring: false);
      _scheduleToastClear();
      await _saveSnapshot();
    } on ParseException catch (error) {
      state = state.copyWith(error: error.message, clearImportStatus: true);
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Unable to read this document: $error',
        clearImportStatus: true,
      );
    }
  }

  // ------------------------------------------------------------- units

  void classifyUnit(String key, UnitKind kind) {
    _mutateUnit(key, (unit) => unit.classified(kind));
  }

  void setUnitSelected(String key, bool selected) {
    _mutateUnit(key, (unit) => unit.copyWith(selected: selected));
  }

  void setSelectedAll(Set<String> keys, bool selected) {
    if (state.isRunning) return;
    state = state.copyWith(
      units: [
        for (final unit in state.units)
          if (keys.contains(unit.key))
            unit.copyWith(selected: selected && !unit.malformed)
          else
            unit,
      ],
    );
  }

  /// Records what the student decided about one finding.
  ///
  /// `open` is stored as "absent" so saved snapshots and older sessions stay a
  /// valid key set — an unseen id simply reads back as open.
  void setFindingStatus(String findingId, FindingStatus status) {
    final next = Map<String, FindingStatus>.from(state.findingStatus);
    if (status == FindingStatus.open) {
      next.remove(findingId);
    } else {
      next[findingId] = status;
    }
    state = state.copyWith(findingStatus: next);
    _saveSnapshot();
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
  /// statuses already agree — the snapshot save is skipped, the state
  /// is not touched, and the returned diff is empty.
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
    _saveSnapshot();
    return VerifyDiff.compute(before: previous, after: next);
  }

  /// Identity test on a `Map<String, FindingStatus>` — true when both
  // maps hold the same key→status pairs. Used by [verifyStatuses] to
  // skip a no-op snapshot save.
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

  /// Replaces the unit with [key] by [mutate]'s result and publishes a new list.
  ///
  /// Units are immutable, so the replacement is a DIFFERENT object: a widget
  /// still holding the old reference cannot observe a change without a rebuild.
  void _mutateUnit(String key, WorkspaceUnit Function(WorkspaceUnit) mutate) {
    if (state.isRunning) return;
    state = state.copyWith(
      units: [
        for (final unit in state.units)
          if (unit.key == key) mutate(unit) else unit,
      ],
    );
    _saveSnapshot();
  }

  // ------------------------------------------------------------- review

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

    final rubricVersion =
        ref.read(rubricProvider).value?.version ??
        RubricConfig.fallback.version;
    final repository = ref.read(reviewRepositoryProvider);

    await _subscription?.cancel();
    _subscription = repository
        .run(
          filtered,
          pdfBytes: imageReviewEnabled ? _pdfBytes : null,
          imageReviewEnabled: imageReviewEnabled,
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

  /// Pages a vision audit would look at, decided offline (visual evidence
  /// or a NAMED diagram type — see [VisionReviewService.candidates]). Zero
  /// when the file bytes are gone (a restored session), which is also what
  /// hides the button: an audit without bytes would render nothing.
  int get diagramAuditCount {
    final document = _document;
    if (document == null || _pdfBytes == null) return 0;
    return _visionService(
      VisionReviewService.noOpAuditor,
    ).candidates(document).length;
  }

  bool get canAuditDiagrams => diagramAuditCount > 0;

  VisionReviewService _visionService(DiagramAuditor auditor) =>
      VisionReviewService(
        auditor: auditor,
        renderPage: (int pageIndex, String _) async {
          final bytes = _pdfBytes;
          if (bytes == null) {
            throw StateError('no file bytes to render page $pageIndex');
          }
          final repository = ref.read(reviewRepositoryProvider);
          final png = await repository.renderPageForAudit(bytes, pageIndex);
          return base64Encode(png);
        },
      );

  /// sds-reviewer steps 4-6 on-device: render each candidate page, two-call
  /// audit through the proxy, ledger rows into [state.referenceFindings].
  ///
  /// Opt-in and explicit, never automatic: a full audit is up to [10]
  /// proxy requests against a 50/day quota, and silently spending 20% of
  /// the day's budget in the background of a review would break the
  /// quota discipline the whole client is built on. Re-running REPLACES
  /// the previous diagram rows (same stable subjects, fresher evidence)
  /// and leaves every other family untouched.
  Future<void> auditDiagrams() async {
    if (state.isAuditingDiagrams) return;
    final document = _document;
    if (document == null || _pdfBytes == null) {
      state = state.copyWith(
        error:
            'The vision audit needs the original file in memory — restored '
            'sessions keep findings but not bytes. Re-import to audit.',
      );
      return;
    }
    final repository = ref.read(reviewRepositoryProvider);
    final service = _visionService(repository.diagramAudit);
    state = state.copyWith(isAuditingDiagrams: true, clearError: true);
    try {
      final outcome = await service.audit(document);
      final kept = state.referenceFindings
          .where((f) => f.check != CheckId.diagramAudit)
          .toList(growable: false);
      state = state.copyWith(
        referenceFindings: [...kept, ...outcome.findings],
        toast: outcome.everythingFailed
            ? null
            : 'Vision audit: ${outcome.auditedPageCount} page(s)'
                  '${outcome.skippedPages.isEmpty ? '' : ', ${outcome.skippedPages.length} skipped (quota cap)'}'
                  '${outcome.failures.isEmpty ? '' : ', ${outcome.failures.length} failed'}',
        clearError: !outcome.everythingFailed,
        error: outcome.everythingFailed
            ? 'Every diagram audit failed (first: ${outcome.failures.first}) — '
                  'the pages were not seen; no verdict was written.'
            : null,
      );
      _scheduleToastClear();
      await _saveSnapshot();
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Diagram audit stopped: $error',
        isAuditingDiagrams: false,
      );
      return;
    }
    state = state.copyWith(isAuditingDiagrams: false);
  }

  /// Share-by-link (plan 6): publish THIS dashboard's HTML twin to the
  /// proxy and return its URL. The report content and the link are built
  /// from the exact same state the export sheet previews — no separate
  /// "server-side truth" to drift. Null while offline (the button hides
  /// there); error state set on failure, like every other paid action.
  bool get canShareReport => !ref.read(mockModeProvider);

  Future<String?> mintShareLink() async {
    if (state.isSharingReport) return null;
    if (!canShareReport) return null;
    final repository = ref.read(reviewRepositoryProvider);
    state = state.copyWith(isSharingReport: true, clearError: true);
    String? link;
    try {
      link = await repository.shareReport(
        html: exportHtml(),
        fileName: state.fileName,
      );
      state = state.copyWith(
        toast: 'Share link created — anyone with the URL can read it.',
        clearError: true,
      );
      _scheduleToastClear();
    } on Object catch (error) {
      state = state.copyWith(error: 'Could not create the share link: $error');
    }
    state = state.copyWith(isSharingReport: false);
    return link;
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
    if (result != null &&
        (progress.stage == ReviewStage.done || result.reviewed > 0)) {
      await _saveSession(result);
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
        await _saveSnapshot();
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
            '$failNote$capNote · saved on this device',
      );
    } else if (progress.stage == ReviewStage.cancelled) {
      final kept = result?.reviewed ?? progress.completed;
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: kept,
        runSkipped: skipped,
        toast: kept > 0
            ? 'Review cancelled · $kept unit(s) reviewed and saved on this device.'
            : 'Review cancelled · nothing had been reviewed yet.',
      );
    } else {
      final kept = result?.reviewed ?? progress.completed;
      final keptNote = kept > 0
          ? ' $kept unit(s) were reviewed and saved on this device.'
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
    await _saveSnapshot();
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

  // ------------------------------------------------------------- ask

  /// Offline keyword search — kept because it is the fallback engine and the
  /// only one available in mock mode.
  List<WorkspaceUnit> askDocument(String question) =>
      AskDocument.search(question, state.units);

  /// Answers one question about the loaded document.
  ///
  /// Prefers the proxy and falls back to the local search, and — critically —
  /// reports which one answered. Before this existed the modal could only ever
  /// call [askDocument], so the proxy's `/ask`, its citation verification and
  /// its "not found" guard were all unreachable code while the app advertised
  /// grounded Q&A as a feature.
  Future<AskOutcome> askQuestion(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: false,
      );
    }

    final offline = AskDocument.search(trimmed, state.units);
    if (offline.isEmpty) {
      // Nothing in the inventory mentions it. Asking the model anyway would be
      // paying for a guess, and the honest answer is that the document says
      // nothing — so no engine runs and no token is spent.
      return const AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: 'Not found in the document.',
        grounded: false,
      );
    }

    if (ref.read(mockModeProvider)) {
      return AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: true,
        units: offline,
      );
    }

    final context = AskDocument.contextFor(trimmed, state.units);
    final repository = ref.read(reviewRepositoryProvider);
    try {
      final response = await repository.ask(
        question: trimmed,
        context: context,
      );
      return AskOutcome(
        engine: AskEngine.model,
        answer: response.answer,
        grounded: response.grounded,
        citations: response.citations,
        model: response.model,
      );
    } on Object catch (error) {
      // A dead proxy used to surface as an empty answer and no explanation.
      // Fall back to what this device can answer and say that is what happened,
      // labelling the engine so the fallback is never mistaken for the model.
      return AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: true,
        units: offline,
        note:
            'The proxy could not answer (${_shortError(error)}). These are '
            'the matching passages from your document instead — no model was '
            'involved.',
      );
    }
  }

  static String _shortError(Object error) {
    final text = '$error';
    return text.length <= 120 ? text : '${text.substring(0, 117)}…';
  }

  // ------------------------------------------------------------- history

  Future<void> loadHistory() async {
    state = state.copyWith(historyLoading: true, clearError: true);
    try {
      final sessions = await _store.list();
      state = state.copyWith(history: sessions, historyLoading: false);
    } on Object catch (error) {
      state = state.copyWith(
        historyLoading: false,
        error: 'Could not load history: $error',
      );
    }
  }

  Future<bool> openSession(String id) async {
    try {
      final session = await _store.open(id);
      if (session == null) {
        state = state.copyWith(toast: 'Could not open review.');
        _scheduleToastClear();
        return false;
      }
      final payload = jsonDecode(session.payloadJson) as Map<String, dynamic>;
      // A session produced by a different parser version may key units
      // differently — reopening it would present triage state that no longer
      // lines up with what a fresh parse yields. Rows written before
      // versioning existed ('') stay openable, as they always were.
      if (session.parserVersion.isNotEmpty &&
          session.parserVersion != kParserVersion) {
        state = state.copyWith(
          toast:
              'Saved review was written by parser '
              '${session.parserVersion}; re-import the document to review '
              'again.',
        );
        _scheduleToastClear();
        return false;
      }
      final units = (payload['units'] as List<dynamic>)
          .map((e) => WorkspaceUnit.fromJson(e as Map<String, dynamic>))
          .toList();
      final resultJson = payload['result'] as Map<String, dynamic>?;
      final syllabusFindings =
          (payload['syllabusFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      final referenceFindings =
          (payload['referenceFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      // Sessions written before the index family existed carry no such key;
      // they round-trip as an empty list like the M2 family did at Round 5.
      final blueprintFindings =
          (payload['blueprintFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      // Sessions written before triage existed carry no such key; every id
      // then reads back as open, which is how they always behaved.
      final findingStatus = <String, FindingStatus>{
        for (final entry
            in (payload['findingStatus'] as Map<dynamic, dynamic>?)?.entries ??
                const <MapEntry<dynamic, dynamic>>[])
          entry.key as String: FindingStatus.fromName(entry.value as String?),
      };
      _document = null; // a restored session reviews no new file
      _pdfBytes = null;
      state = state.copyWith(
        hasDocument: true,
        // Only `units` is load-bearing; the rest is display metadata. Casting
        // those with `as String` / `as int` used to throw on a payload that was
        // merely missing an optional field, which the catch-all turned into
        // "Could not open review" and made the session permanently unopenable.
        fileName: (payload['fileName'] as String?) ?? session.fileName,
        pageCount: (payload['pageCount'] as int?) ?? 0,
        sizeLabel: (payload['sizeLabel'] as String?) ?? '',
        isDemo: (payload['isDemo'] as bool?) ?? false,
        units: units,
        syllabusFindings: syllabusFindings,
        referenceFindings: referenceFindings,
        blueprintFindings: blueprintFindings,
        findingStatus: findingStatus,
        diagramPageCount: (payload['diagramPageCount'] as int?) ?? 0,
        imageReviewAvailable: false,
        imageReviewedCount: 0,
        clearImageCoverage: true,
        result: resultJson == null
            ? null
            : WorkspaceReviewResult.fromJson(resultJson),
        documentFingerprint: session.fingerprint,
        parserVersion: session.parserVersion,
        // The summary bar describes the run that just finished in THIS
        // session. `copyWith` carries `runReviewed` over, so opening a saved
        // review would otherwise re-show a bar about a run the user cannot
        // see in this context.
        runReviewed: 0,
        runSummaryDismissed: true,
        toast: 'Saved review restored.',
        restoring: false,
      );
      _scheduleToastClear();
      return true;
    } on Object catch (error) {
      state = state.copyWith(toast: 'Could not open review: $error');
      _scheduleToastClear();
      return false;
    }
  }

  Future<void> deleteSession(String id) async {
    await _store.delete(id);
    await loadHistory();
  }

  // ------------------------------------------------------------- export

  String exportMarkdown() => buildMarkdownReport(
    fileName: state.fileName,
    offline: ref.read(mockModeProvider),
    result: state.result,
    units: state.units,
    // Both engines' output, in one report: the offline syllabus checks used to
    // live only on their own tab and never made it into anything a supervisor
    // could read.
    syllabusFindings: state.syllabusFindings,
    // M2 family must reach the report too — the OTES pattern (63/63 use
    // cases without a Postcondition) lives here, not in the syllabus list.
    referenceFindings: state.referenceFindings,
    // Document-index family: same offline evidence, its own family label.
    blueprintFindings: state.blueprintFindings,
    diagramPageCount: state.diagramPageCount,
    imageReviewAvailable: state.imageReviewAvailable,
    imageReviewedCount: state.imageReviewedCount,
    imageCoverage: state.imageCoverage,
    findingStatus: state.findingStatus,
  );

  /// Writes the report to a file the user chooses.
  ///
  /// Returns the destination as the platform reported it, or null when the
  /// user cancelled. Copying to the clipboard is still offered, but a report
  /// you cannot attach to a submission is not really an export.
  Future<String?> saveReportToFile() async {
    final report = exportMarkdown();
    return _exporter.save(fileName: _reportFileName(), contents: report);
  }

  /// Structured twin of [exportMarkdown] — same inputs, same numbers, one
  /// shared schema for a server or web tool (goal §4 Output row).
  String exportJson() => const JsonEncoder.withIndent('  ').convert(
    buildJsonReport(
      fileName: state.fileName,
      offline: ref.read(mockModeProvider),
      result: state.result,
      units: state.units,
      syllabusFindings: state.syllabusFindings,
      referenceFindings: state.referenceFindings,
      diagramPageCount: state.diagramPageCount,
      imageReviewAvailable: state.imageReviewAvailable,
      imageReviewedCount: state.imageReviewedCount,
      imageCoverage: state.imageCoverage,
      findingStatus: state.findingStatus,
    ),
  );

  /// Writes the JSON report to a file the user chooses. Same dialog, same
  /// contract, and the same error semantics as [saveReportToFile].
  Future<String?> saveJsonReportToFile() async {
    final report = exportJson();
    return _exporter.save(
      fileName: _reportFileName(extension: 'json'),
      contents: report,
    );
  }

  /// Dashboard twin of [exportMarkdown] — the brief's Report row asks for a
  /// dashboard a supervisor opens in a browser, not just prose for a repo.
  /// Same inputs as both twins; the numbers agree by construction.
  String exportHtml() => buildHtmlReport(
    fileName: state.fileName,
    offline: ref.read(mockModeProvider),
    result: state.result,
    units: state.units,
    syllabusFindings: state.syllabusFindings,
    referenceFindings: state.referenceFindings,
    blueprintFindings: state.blueprintFindings,
    diagramPageCount: state.diagramPageCount,
    imageReviewAvailable: state.imageReviewAvailable,
    imageReviewedCount: state.imageReviewedCount,
    imageCoverage: state.imageCoverage,
    findingStatus: state.findingStatus,
  );

  /// Writes the HTML dashboard to a file the user chooses. Same dialog and
  /// error contract as the markdown and JSON twins.
  Future<String?> saveHtmlReportToFile() async {
    final report = exportHtml();
    return _exporter.save(
      fileName: _reportFileName(extension: 'html'),
      contents: report,
      mimeType: 'text/html',
    );
  }

  /// Opens the OS share sheet with the markdown report attached. The third
  /// leg of the brief's Output row ("ledger.md + JSON + share sheet") — the
  /// native AirDrop/Drive/Mail flow is how a report actually reaches a
  /// supervisor on mobile. Shares the markdown, not the JSON: the share
  /// target is a human reader.
  Future<String> shareReport() =>
      _exporter.share(fileName: _reportFileName(), contents: exportMarkdown());

  String _reportFileName({String extension = 'md'}) {
    final base = state.fileName.trim().isEmpty ? 'srs' : state.fileName;
    final stem = base.contains('.')
        ? base.substring(0, base.lastIndexOf('.'))
        : base;
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    return 'srs-review-$safe-$stamp.$extension';
  }

  // ------------------------------------------------------------- toast

  void dismissToast() {
    _toastTimer?.cancel();
    state = state.copyWith(clearToast: true);
  }

  void _scheduleToastClear() {
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 4500), () {
      state = state.copyWith(clearToast: true);
    });
  }

  // ------------------------------------------------------------- persistence

  Future<void> _saveSnapshot() async {
    if (!state.hasDocument) return;
    final payload = jsonEncode({
      'fileName': state.fileName,
      'pageCount': state.pageCount,
      'sizeLabel': state.sizeLabel,
      'isDemo': state.isDemo,
      'units': state.units.map((u) => u.toJson()).toList(),
      'syllabusFindings': state.syllabusFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      'referenceFindings': state.referenceFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      // Blueprint findings persist like the other two families so older
      // snapshots (no such key) restore an empty list instead of breaking.
      'blueprintFindings': state.blueprintFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      'findingStatus': state.findingStatus.map(
        (id, status) => MapEntry(id, status.name),
      ),
      'diagramPageCount': state.diagramPageCount,
      'result': state.result?.toJson(),
      'documentFingerprint': state.documentFingerprint,
      'parserVersion': state.parserVersion,
    });
    try {
      await _store.saveSnapshot(payload);
    } on Object {
      // Persistence is best-effort: losing the snapshot never blocks a review.
    }
  }

  Future<void> _restoreSnapshot() async {
    try {
      final raw = await _store.loadSnapshot();
      // The user may already have loaded a demo or a document while the
      // snapshot was being read — never clobber live state, never touch a
      // disposed provider.
      if (!ref.mounted) return;
      if (state.hasDocument) {
        state = state.copyWith(restoring: false);
        return;
      }
      if (raw == null) {
        state = state.copyWith(restoring: false);
        return;
      }
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      // Parser gate: a snapshot written by a different parser version may
      // yield different units — or different unit keys — for the same text,
      // so its saved statuses and result must never be reused. Payloads
      // written before versioning carried no key and restore as always.
      final savedParserVersion = payload['parserVersion'] as String?;
      if (savedParserVersion != null && savedParserVersion != kParserVersion) {
        state = WorkspaceState(
          restoring: false,
          toast:
              'Saved workspace was written by parser $savedParserVersion; '
              're-import the document to start fresh.',
        );
        _scheduleToastClear();
        return;
      }
      final units = (payload['units'] as List<dynamic>)
          .map((e) => WorkspaceUnit.fromJson(e as Map<String, dynamic>))
          .toList();
      if (units.isEmpty) {
        state = state.copyWith(restoring: false);
        return;
      }
      final resultJson = payload['result'] as Map<String, dynamic>?;
      final syllabusFindings =
          (payload['syllabusFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      // M2 reference findings: written by Round 5+ snapshots. Snapshots
      // without the key (Round ≤4) round-trip as an empty list so the
      // dashboard renders no M2 rows for older sessions instead of breaking.
      final referenceFindings =
          (payload['referenceFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      // Sessions written before the index family existed carry no such key;
      // they round-trip as an empty list like the M2 family did at Round 5.
      final blueprintFindings =
          (payload['blueprintFindings'] as List<dynamic>?)
              ?.map(
                (entry) => DeterministicFinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      final findingStatus = <String, FindingStatus>{
        for (final entry
            in (payload['findingStatus'] as Map<dynamic, dynamic>?)?.entries ??
                const <MapEntry<dynamic, dynamic>>[])
          entry.key as String: FindingStatus.fromName(entry.value as String?),
      };
      _document = null;
      _pdfBytes = null;
      state = WorkspaceState(
        hasDocument: true,
        fileName: payload['fileName'] as String,
        pageCount: payload['pageCount'] as int,
        sizeLabel: payload['sizeLabel'] as String,
        isDemo: payload['isDemo'] as bool,
        units: units,
        syllabusFindings: syllabusFindings,
        referenceFindings: referenceFindings,
        blueprintFindings: blueprintFindings,
        findingStatus: findingStatus,
        diagramPageCount: (payload['diagramPageCount'] as int?) ?? 0,
        result: resultJson == null
            ? null
            : WorkspaceReviewResult.fromJson(resultJson),
        documentFingerprint: payload['documentFingerprint'] as String? ?? '',
        parserVersion: savedParserVersion ?? '',
        restoring: false,
      );
    } on Object {
      state = state.copyWith(restoring: false);
    }
  }

  Future<void> _saveSession(WorkspaceReviewResult result) async {
    final payload = jsonEncode({
      'fileName': state.fileName,
      'pageCount': state.pageCount,
      'sizeLabel': state.sizeLabel,
      'isDemo': state.isDemo,
      'units': state.units.map((u) => u.toJson()).toList(),
      'syllabusFindings': state.syllabusFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      'referenceFindings': state.referenceFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      // Blueprint findings persist like the other two families so older
      // snapshots (no such key) restore an empty list instead of breaking.
      'blueprintFindings': state.blueprintFindings
          .map((finding) => finding.toJson())
          .toList(growable: false),
      'findingStatus': state.findingStatus.map(
        (id, status) => MapEntry(id, status.name),
      ),
      'diagramPageCount': state.diagramPageCount,
      'result': result.toJson(),
      'documentFingerprint': state.documentFingerprint,
      'parserVersion': state.parserVersion,
    });
    await _store.save(
      SavedSession(
        id: 'sess-${DateTime.now().microsecondsSinceEpoch}',
        fileName: state.fileName,
        fingerprint: state.documentFingerprint,
        parserVersion: state.parserVersion,
        payloadJson: payload,
        createdAt: DateTime.now(),
      ),
    );
    await loadHistory();
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

final workspaceViewModelProvider =
    NotifierProvider<WorkspaceViewModel, WorkspaceState>(
      WorkspaceViewModel.new,
    );
