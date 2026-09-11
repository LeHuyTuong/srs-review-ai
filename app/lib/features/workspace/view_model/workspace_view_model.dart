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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../../core/providers.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/checks/syllabus_checks.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../data/services/session_store.dart';

import '../models/ask_document.dart';
import '../models/demo_units.dart';
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
  });

  final bool hasDocument;
  final String fileName;
  final int pageCount;
  final String sizeLabel;
  final bool isDemo;
  final List<WorkspaceUnit> units;
  final List<DeterministicFinding> syllabusFindings;
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

  Duration? get runElapsed {
    final start = runStartedAt;
    if (start == null || !isRunning) return null;
    return DateTime.now().difference(start);
  }

  bool get isRunning => progress != null && _runningStages.contains(progress!.stage);
  bool get hasResult => result != null;

  int get selectedCount => units.where((u) => u.selected).length;
  int get attentionCount => units.where((u) => u.malformed).length;
  int get useCaseCount => units.where((u) => u.kind == UnitKind.useCase).length;
  int get otherRequirementsCount => units
      .where(
        (u) =>
            u.kind == UnitKind.businessRule ||
            u.kind == UnitKind.nonFunctional ||
            u.kind == UnitKind.functional,
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
  }) => WorkspaceState(
    hasDocument: hasDocument ?? this.hasDocument,
    fileName: fileName ?? this.fileName,
    pageCount: pageCount ?? this.pageCount,
    sizeLabel: sizeLabel ?? this.sizeLabel,
    isDemo: isDemo ?? this.isDemo,
    units: units ?? this.units,
    syllabusFindings: syllabusFindings ?? this.syllabusFindings,
    result: clearResult ? null : (result ?? this.result),
    progress: clearProgress ? null : (progress ?? this.progress),
    error: clearError ? null : (error ?? this.error),
    toast: clearToast ? '' : (toast ?? this.toast),
    importStatus:
        clearImportStatus ? null : (importStatus ?? this.importStatus),
    history: history ?? this.history,
    historyLoading: historyLoading ?? this.historyLoading,
    restoring: restoring ?? this.restoring,
    runStartedAt:
        clearRunStartedAt ? null : (runStartedAt ?? this.runStartedAt),
    runReviewed: runReviewed ?? this.runReviewed,
    runSkipped: runSkipped ?? this.runSkipped,
  );
}

class WorkspaceViewModel extends Notifier<WorkspaceState> {
  SrsDocument? _document;
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
    final units = unitsFromDocument(document);
    for (final unit in units) {
      if (_demoMalformedIds.contains(unit.id)) {
        unit.classify(UnitKind.unknown);
      }
    }
    _document = document;
    state = WorkspaceState(
      hasDocument: true,
      fileName: demoFileName,
      pageCount: demoPageCount,
      sizeLabel: '27.37 MB',
      isDemo: true,
      units: units,
      syllabusFindings: SyllabusChecks(
        RubricConfig.fallback,
      ).runAll(document),
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
        // user cancelled the picker
        state = state.copyWith(clearImportStatus: true);
        return;
      }
      _document = loaded.document;
      state = WorkspaceState(
        hasDocument: true,
        fileName: loaded.document.fileName,
        pageCount: loaded.document.pageCount,
        sizeLabel: _formatBytes(loaded.sizeBytes),
        isDemo: false,
        units: unitsFromDocument(loaded.document),
        syllabusFindings: loaded.findings,
        toast:
            '${loaded.document.requirements.length} units extracted. '
            'All detected IDs have been preserved.',
      ).copyWith(restoring: false);
      _scheduleToastClear();
      await _saveSnapshot();
    } on ParseException catch (error) {
      state = state.copyWith(
        error: error.message,
        clearImportStatus: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Unable to read this document: $error',
        clearImportStatus: true,
      );
    }
  }

  // ------------------------------------------------------------- units

  void classifyUnit(String key, UnitKind kind) {
    _mutateUnit(key, (unit) => unit.classify(kind));
  }

  void setUnitSelected(String key, bool selected) {
    _mutateUnit(key, (unit) => unit.selected = selected);
  }

  void setSelectedAll(Set<String> keys, bool selected) {
    if (state.isRunning) return;
    state = state.copyWith(
      units: [
        for (final unit in state.units)
          if (keys.contains(unit.key))
            unit..selected = selected && !unit.malformed
          else
            unit,
      ],
    );
  }

  void _mutateUnit(String key, void Function(WorkspaceUnit) mutate) {
    if (state.isRunning) return;
    for (final unit in state.units) {
      if (unit.key == key) mutate(unit);
    }
    // WorkspaceUnit is mutable in place; a fresh state object tells listeners.
    state = state.copyWith(units: [...state.units]);
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

    final itemById = {
      for (final item in document.requirements) item.id: item,
    };
    final selectedItems = [
      for (final unit in capped)
        if (itemById[unit.id] != null) itemById[unit.id]!,
    ];
    final filtered = SrsDocument(
      fileName: state.fileName,
      pageCount: document.pageCount,
      pageTexts: document.pageTexts,
      requirements: selectedItems,
      imagePageIndexes: document.imagePageIndexes,
    );

    state = state.copyWith(
      clearError: true,
      clearResult: true,
      runStartedAt: DateTime.now(),
      runReviewed: 0,
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
        ref.read(rubricProvider).value?.version ?? RubricConfig.fallback.version;
    final repository = ref.read(reviewRepositoryProvider);

    await _subscription?.cancel();
    _subscription = repository.run(
      filtered,
      onComplete: (run) {
        final result = WorkspaceReviewResult.fromRun(
          run: run,
          document: filtered,
          units: state.units,
          rubricVersion: rubricVersion,
        );
        state = state.copyWith(
          result: result,
          units: [
            for (final unit in state.units)
              unit..status = unit.selected
                  ? UnitStatus.reviewed
                  : UnitStatus.skipped,
          ],
        );
      },
    ).listen(
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
        state = state.copyWith(
          clearProgress: true,
          error: 'Review failed. Your selection is preserved.',
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
    if (progress.stage == ReviewStage.done) {
      final result = state.result;
      if (result != null) {
        await _saveSession(result);
      }
      final reviewed = result?.reviewed ?? 0;
      final findings = result?.findings.length ?? 0;
      final failed = result?.failed ?? 0;
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
        toast:
            '$reviewed units reviewed · $findings verified findings'
            '$failNote$capNote · saved on this device',
      );
    } else if (progress.stage == ReviewStage.cancelled) {
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: progress.completed,
        runSkipped: skipped,
        toast: 'Review cancelled · ${progress.completed} units kept.',
      );
    } else {
      state = state.copyWith(
        clearProgress: true,
        runStartedAt: DateTime.now(),
        runReviewed: progress.completed,
        runSkipped: skipped,
        error: progress.error ?? 'Review failed. Your selection is preserved.',
      );
    }
    _scheduleToastClear();
    await _saveSnapshot();
  }

  void cancelReview() {
    ref.read(reviewRepositoryProvider).cancel();
  }

  // ------------------------------------------------------------- ask

  List<WorkspaceUnit> askDocument(String question) =>
      AskDocument.search(question, state.units);

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
      final payload =
          jsonDecode(session.payloadJson) as Map<String, dynamic>;
      final units = (payload['units'] as List<dynamic>)
          .map((e) => WorkspaceUnit.fromJson(e as Map<String, dynamic>))
          .toList();
      final resultJson = payload['result'] as Map<String, dynamic>?;
      _document = null; // a restored session reviews no new file
      state = state.copyWith(
        hasDocument: true,
        fileName: payload['fileName'] as String,
        pageCount: payload['pageCount'] as int,
        sizeLabel: payload['sizeLabel'] as String,
        isDemo: payload['isDemo'] as bool,
        units: units,
        syllabusFindings: const [],
        result: resultJson == null
            ? null
            : WorkspaceReviewResult.fromJson(resultJson),
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
  );

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
      'result': state.result?.toJson(),
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
      final units = (payload['units'] as List<dynamic>)
          .map((e) => WorkspaceUnit.fromJson(e as Map<String, dynamic>))
          .toList();
      if (units.isEmpty) {
        state = state.copyWith(restoring: false);
        return;
      }
      final resultJson = payload['result'] as Map<String, dynamic>?;
      _document = null;
      state = WorkspaceState(
        hasDocument: true,
        fileName: payload['fileName'] as String,
        pageCount: payload['pageCount'] as int,
        sizeLabel: payload['sizeLabel'] as String,
        isDemo: payload['isDemo'] as bool,
        units: units,
        result: resultJson == null
            ? null
            : WorkspaceReviewResult.fromJson(resultJson),
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
      'result': result.toJson(),
    });
    await _store.save(
      SavedSession(
        id: 'sess-${DateTime.now().microsecondsSinceEpoch}',
        fileName: state.fileName,
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
