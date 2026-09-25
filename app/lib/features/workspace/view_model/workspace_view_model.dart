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
import '../../../data/checks/format_layout_checks.dart';
import '../../../data/checks/project_info_checks.dart';
import '../../../data/checks/reference_checks.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/checks/syllabus_checks.dart';
import '../../../data/checks/verifier.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/document_map.dart';
import '../../../data/models/human_issue.dart';
import '../../../data/models/project_info.dart';
import '../../../data/models/review_models.dart' show Severity;
import '../../../data/models/review_progress.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/services/report_exporter.dart';
import '../../../data/services/session_store.dart';
import '../../../data/services/vision_review_service.dart';

import '../models/ask_document.dart';
import '../models/demo_units.dart';
import '../models/docx_report.dart';
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

/// The line a finished run owes the user when this host has no PDF renderer.
///
/// A run that asked for page images and never got one still reviews every
/// diagram-shaped unit — from its extracted text. Without this sentence that
/// run looks identical to one whose pictures were graded, and the verdict's
/// diagram component would read as if a model had looked at the drawings.
/// English here, Vietnamese in the presentation layer, like every other
/// application-owned message; the leading separator lets callers append it to
/// a one-line summary.
const String kNoPdfRendererNote =
    ' · this platform has no PDF renderer — the diagrams were reviewed from '
    'text only, not from their images';

/// [kNoPdfRendererNote] without the summary separator, for a standalone line.
const String kNoPdfRendererNotice =
    'This platform has no PDF renderer — the '
    'diagrams were reviewed from text only, not from their images.';

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
    this.recentSessions = const [],
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
    this.executionLogs = const [],
    this.pageTexts = const [],
    this.uploadUri,
    this.projectInfo,
    this.projectName = '',
    this.humanIssues = const [],
  });

  /// Server upload URI for document figure rendering and tight crops.
  final String? uploadUri;

  /// What the user declared about the project in the project-info form —
  /// the human side of the "Thông tin chung" review (the document side is
  /// whatever its cover page actually says). Null until the form is saved.
  final ProjectInfo? projectInfo;

  /// Container name created in workflow step 1 ("Tạo project").
  ///
  /// Deliberately NOT [ProjectInfo]projectName: that one is the đề tài title
  /// declared for the cover-page check (§F.3); THIS is the bucket saved
  /// sessions are grouped under in the History tab so results from different
  /// submission rounds never mix (workflow Bước 1→3). '' until step 1 runs.
  final String projectName;

  /// Issues the reviewer typed in by hand (Report tab) — the "con người"
  /// source next to the AI rows. Travel with saved sessions so the
  /// merged report survives restarts; carried across re-imports like the
  /// project declaration, because they annotate the project, not the file.
  final List<HumanIssue> humanIssues;

  /// Audit trail of AI actions and validation pipeline events.
  final List<String> executionLogs;

  /// Text content per page in the document.
  final List<String> pageTexts;

  bool get canRenderPdf =>
      imageReviewAvailable || (uploadUri != null && uploadUri!.isNotEmpty);

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

  /// The newest few sessions, for the landing card ("Tiếp tục gần đây").
  ///
  /// Separate from [history] on purpose: the History tab needs all 30 rows and
  /// their payloads (it groups them by project), while the landing screen
  /// needs three titles — and pulls only those from the store
  /// ([SessionStore.listRecent]) instead of loading the whole history to
  /// render a shortcut.
  final List<SavedSession> recentSessions;

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
  /// page image. This is not persisted with saved sessions.
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

  /// True when the last run wanted page images and this host could not
  /// rasterize a single page, so no diagram was ever put in front of the model.
  ///
  /// Derived from the run's own coverage, never from the platform: a run with
  /// image review switched off (DOCX, mock mode, a session without bytes) says
  /// nothing about the renderer and must stay quiet.
  bool get diagramsWereTextOnly => imageCoverage?.rendererUnavailable ?? false;

  /// Identity of the reviewed content: the document fingerprint and the
  /// parser version that produced it. Saved sessions record both so opening
  /// one can refuse to reuse review results across parser changes.
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
  /// in saved sessions, so a `hasResult` gate would re-open the app — or a
  /// session from History — onto a summary of a run the user never saw here.
  /// `runReviewed` only ever describes the run that just finished in this
  /// context.
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
    List<SavedSession>? recentSessions,
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
    List<String>? executionLogs,
    List<String>? pageTexts,
    String? uploadUri,
    bool clearUploadUri = false,
    ProjectInfo? projectInfo,
    String? projectName,
    bool clearProjectInfo = false,
    List<HumanIssue>? humanIssues,
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
    recentSessions: recentSessions ?? this.recentSessions,
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
    executionLogs: executionLogs ?? this.executionLogs,
    pageTexts: pageTexts ?? this.pageTexts,
    uploadUri: clearUploadUri ? null : (uploadUri ?? this.uploadUri),
    projectInfo: clearProjectInfo ? null : (projectInfo ?? this.projectInfo),
    projectName: projectName ?? this.projectName,
    humanIssues: humanIssues ?? this.humanIssues,
  );
}

class WorkspaceViewModel extends Notifier<WorkspaceState> {
  /// Stateless and platform-delegating, so it needs no provider: constructing
  /// it inline keeps the ViewModel constructible in tests that only care about
  /// review behaviour.
  static const ReportExporter _exporter = ReportExporter();

  /// How many saved runs the landing card offers. Three is a shortcut back
  /// into the most recent submission round, not a second History tab.
  static const int _recentSessionCount = 3;

  SrsDocument? _document;
  Uint8List? _pdfBytes;

  /// Server-side anatomy of the CURRENT import (`/documents/analyze`) and the
  /// `upload://` ref render calls need. Both are session-transient like
  /// [_pdfBytes]: a session opened from History has no bytes on the server
  /// either, so the vision audit falls back to the heuristic path there —
  /// exactly like it does when the analyze call fails.
  DocumentMap? _documentMap;
  String? _uploadUri;
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
    // No auto-restore of a previous workspace on startup (decision
    // 2026-09-23): opening the app must land on the guided first-run flow
    // (Bước 1→3), never inside the previous session. Saved runs stay reachable
    // via History (openSession), which carries units, findings, triage and the
    // declaration on its own.
    //
    // Two small things ARE restored, because a restart used to throw them
    // away and nobody asked for that: the DRAFT (the project container and the
    // declaration the user typed in steps 1–2) and the landing card's short
    // list of recent sessions.
    scheduleMicrotask(_restoreDraft);
    scheduleMicrotask(_loadRecentSessions);
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

  void _log(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    state = state.copyWith(
      executionLogs: [...state.executionLogs, '[$timeStr] $message'],
    );
  }

  // --------------------------------------------------------- project info form

  /// Saves what the user declared in the project-info form.
  ///
  /// Deliberately tiny: the form owns validation (via the model's
  /// `isValid*` helpers), this method records the result, refreshes the §F.3
  /// findings against it and leaves an audit-log line, so the "Thông tin
  /// chung" review and the exported report read one source of truth.
  /// Persisted as part of the workspace draft (and, once a run finishes, of
  /// the session itself) so the declaration and the §F.3 findings derived from
  /// it survive a restart together.
  void setProjectInfo(ProjectInfo info) {
    state = state.copyWith(projectInfo: info);
    _refreshProjectInfoFindings();
    _log(
      'Lưu thông tin dự án "${info.projectName}" '
      '(${info.students.length} thành viên)',
    );
    // Fire-and-forget: the declaration is step-2 work with no other home — no
    // session exists until a run finishes, so without the draft a restart
    // silently eats the form.
    _saveDraft();
  }

  /// Workflow step 1 — creates (or renames) the project container.
  ///
  /// A DIFFERENT name is treated as a NEW project: the declaration typed for
  /// the old one describes the old đề tài, so it — and the §F.3 findings
  /// derived from it — are dropped rather than silently carried into a
  /// different history bucket. Re-submitting the same trimmed name is a
  /// no-op and keeps the form. The loaded document/results are left alone:
  /// they may have cost quota, and step 3 (re-import) replaces them
  /// explicitly.
  void createProject(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.projectName) return;
    state = state.copyWith(projectName: trimmed, clearProjectInfo: true);
    _refreshProjectInfoFindings();
    _log('Tạo project "$trimmed"');
    // Same fire-and-forget contract as setProjectInfo: the container name is
    // what the landing flow and the History grouping must still show after a
    // restart, even before any run has finished.
    _saveDraft();
  }

  /// Report tab — records a reviewer-authored issue (the "con người"
  /// source beside the model's rows).
  ///
  /// An empty title is a no-op (the dialog validates first); ids are unique
  /// by creation microsecond so two issues in the same second never
  /// collapse into one row.
  void addHumanIssue({
    required String title,
    String detail = '',
    Severity severity = Severity.medium,
    String? section,
  }) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;
    state = state.copyWith(
      humanIssues: [
        ...state.humanIssues,
        HumanIssue(
          id: 'human-${DateTime.now().microsecondsSinceEpoch}',
          title: trimmedTitle,
          detail: detail.trim(),
          severity: severity,
          section: section?.trim(),
          createdAt: DateTime.now(),
        ),
      ],
    );
    _log('Reviewer added issue "$trimmedTitle" (${severity.name})');
    _saveDraft();
  }

  /// Drops one reviewer-authored issue. Like every other sync mutation it
  /// persists best-effort right away so a restart cannot resurrect the row.
  void removeHumanIssue(String id) {
    state = state.copyWith(
      humanIssues: state.humanIssues.where((issue) => issue.id != id).toList(),
    );
    _saveDraft();
  }

  /// §F.3 (rulebook 1.7-draft) — recompute the declared-vs-cover findings
  /// from the CURRENT declaration and page texts.
  ///
  /// Replaces any previous run of the same check instead of appending: the
  /// user may save the form three times, and three stacked copies of one
  /// mismatch would read as three defects. Called after import and after
  /// every save.
  void _refreshProjectInfoFindings() {
    final kept = state.referenceFindings
        .where((finding) => finding.check != CheckId.projectInfoMismatch)
        .toList();
    final declared = state.projectInfo;
    state = state.copyWith(
      referenceFindings: declared == null
          ? kept
          : [
              ...kept,
              ...const ProjectInfoChecks().declaredVsCover(
                declared,
                state.pageTexts,
              ),
            ],
    );
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
    _documentMap = null;
    _uploadUri = null;
    state = WorkspaceState(
      hasDocument: true,
      fileName: demoFileName,
      pageCount: demoPageCount,
      sizeLabel: '27.37 MB',
      isDemo: true,
      units: units,
      // Like a re-import: the container name and the declaration belong to
      // the PROJECT, not to whichever file is open — dropping them here
      // would erase workflow steps 1+2 the moment someone opens the demo.
      projectInfo: state.projectInfo,
      projectName: state.projectName,
      humanIssues: state.humanIssues,
      syllabusFindings: SyllabusChecks(RubricConfig.fallback).runAll(document),
      referenceFindings: [
        ...const ReferenceChecks().runAll(document),
        // §F.5 rides the repository list at import (document_repository);
        // the demo path computes the same checks here because it bypasses
        // the repository entirely. The dashboard splits them back out by
        // [CheckId.isFormatCheck] into the Format & Layout section.
        ...const FormatLayoutChecks().runAll(document),
      ],
      blueprintFindings: const BlueprintChecks().runAll(document.blueprint),
      diagramPageCount: document.imagePageIndexes.length,
      imageReviewAvailable: false,
      imageReviewedCount: 0,
      imageCoverage: null,
      documentFingerprint: document.documentFingerprint,
      parserVersion: kParserVersion,
      pageTexts: document.pageTexts,
      toast:
          '${units.length} units extracted. All detected IDs have been preserved.',
    );
    // Fresh page texts — re-verify the carried declaration against them so
    // §F.3 never lags one document behind (same contract as importDocument).
    _refreshProjectInfoFindings();
    _scheduleToastClear();
    _log('Tải tài liệu mẫu: $demoFileName ($demoPageCount trang)');
    _log(
      'Trích xuất: ${units.length} yêu cầu, ${document.imagePageIndexes.length} trang sơ đồ',
    );
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
      // A new file invalidates the previous file's server anatomy — reset
      // BEFORE the analyze attempt so a failed analyze never pairs the old
      // map with the new document.
      _documentMap = null;
      _uploadUri = null;
      state = WorkspaceState(
        hasDocument: true,
        fileName: loaded.document.fileName,
        pageCount: loaded.document.pageCount,
        sizeLabel: _formatBytes(loaded.sizeBytes),
        isDemo: false,
        units: unitsFromDocument(loaded.document),
        syllabusFindings: loaded.findings,
        referenceFindings: loaded.referenceFindings,
        blueprintFindings: [
          ...loaded.blueprintFindings,
          // §F.4 — chapter order reads the resolved index, which only exists
          // here; the declaration-based §F.3 is refreshed separately below,
          // because it must also react to later form saves.
          ...const ProjectInfoChecks().sectionOrder(loaded.document.blueprint),
        ],
        // The declaration is about the PROJECT, not the file: replacing the
        // document must not silently discard what the user typed.
        projectInfo: state.projectInfo,
        projectName: state.projectName,
        // Reviewer-authored issues annotate the project, not the file: a
        // re-import must not discard what the reviewer already recorded.
        humanIssues: state.humanIssues,
        // How many pages look like diagrams. Recorded at import so the report
        // can distinguish diagram detection from actual image review.
        diagramPageCount: loaded.document.imagePageIndexes.length,
        imageReviewAvailable: loaded.pdfBytes != null,
        imageReviewedCount: 0,
        imageCoverage: null,
        documentFingerprint: loaded.document.documentFingerprint,
        parserVersion: kParserVersion,
        pageTexts: loaded.document.pageTexts,
        toast:
            '${loaded.document.requirements.length} units extracted. '
            'All detected IDs have been preserved.',
      );
      // §F.3 needs BOTH sides of the comparison: the declaration survived the
      // re-import above (projectInfo is carried over), and these are fresh
      // page texts to check it against.
      _refreshProjectInfoFindings();
      _scheduleToastClear();
      await _analyzeDocumentOnServer(
        bytes: loaded.pdfBytes,
        fileName: loaded.document.fileName,
      );
    } on ParseException catch (error) {
      state = state.copyWith(error: error.message, clearImportStatus: true);
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Unable to read this document: $error',
        clearImportStatus: true,
      );
    }
  }

  /// Server-side anatomy pass (sds-reviewer step 1, EXTRACT) after a
  /// successful import: upload the bytes once, then `/documents/analyze`
  /// returns real section spans and every figure region with its bbox —
  /// including the vector UML the client parser cannot see.
  ///
  /// Strictly an upgrade, never a blocker: mock mode, DOCX imports (no page
  /// bytes), a dead proxy, or an unparseable file all leave [_documentMap]
  /// null and every consumer silently takes the heuristic path it already
  /// had. On success the diagram-page count is REPLACED by the truthful
  /// figure-page count so the UI stops quoting the text-density guess.
  Future<void> _analyzeDocumentOnServer({
    required Uint8List? bytes,
    required String fileName,
  }) async {
    if (bytes == null) return; // DOCX/demo: nothing to upload yet
    try {
      // Read INSIDE the try: a provider that cannot build (no configured
      // proxy URL, storage failure) must not turn a good import into an error.
      final service = ref.read(documentMapServiceProvider);
      if (service == null) return; // mock mode
      final analysis = await service.analyzeDocument(
        fileName: fileName,
        bytes: bytes,
      );
      // The user may have cleared or re-imported while the upload ran —
      // a stale map must never attach itself to a different document.
      if (!ref.mounted || _pdfBytes != bytes) return;
      _documentMap = analysis.map;
      _uploadUri = analysis.uploadUri;
      state = state.copyWith(
        uploadUri: analysis.uploadUri,
        imageReviewAvailable: true,
        diagramPageCount: analysis.map.figurePages.length,
        toast:
            'Server anatomy: ${analysis.map.figureCount} figure(s) on '
            '${analysis.map.figurePages.length} page(s) detected — the '
            'vision audit will read tight crops.',
      );
      _log(
        'Server anatomy: Phân tích tài liệu hoàn tất (${analysis.map.figureCount} sơ đồ, uploadUri: ${analysis.uploadUri})',
      );
      _scheduleToastClear();
    } on Object {
      // Heuristic fallback stays. The import already succeeded; a failed
      // anatomy pass must not turn a good import into an error.
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

  /// Identity test on a `Map<String, FindingStatus>` — true when both
  // maps hold the same key→status pairs. Used by [verifyStatuses] to
  // skip a no-op write.
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

  bool get hasPdfBytes => _pdfBytes != null && _pdfBytes!.isNotEmpty;

  /// True when results are on screen but the original file is gone — the
  /// state a restored session lands in. The workflow's "đánh giá lại" path
  /// must ask for an explicit re-import instead of pretending the bytes are
  /// still in memory ([runReview] refuses with the matching message).
  bool get needsReImport => state.hasDocument && _document == null;

  bool get canRenderPdf =>
      state.canRenderPdf ||
      hasPdfBytes ||
      (_uploadUri != null && _uploadUri!.isNotEmpty);

  /// Renders a single PDF page to PNG bytes for inspection / preview.
  /// Prioritizes the server's `/documents/render` endpoint via [DocumentMapService]
  /// for instant PyMuPDF rasterization; if unavailable or offline, falls back
  /// to in-memory `_pdfBytes` locally via [reviewRepositoryProvider].
  Future<Uint8List?> renderPageImage(int pageIndex) async {
    var uploadUri = _uploadUri ?? state.uploadUri;
    final mapService = ref.read(documentMapServiceProvider);

    // Fast path: high-fidelity PyMuPDF render from server
    if (uploadUri != null && mapService != null) {
      try {
        final image = await mapService.renderFigure(
          uploadUri: uploadUri,
          pageIndex: pageIndex,
        );
        if (image.isNotEmpty) return image;
      } catch (e) {
        _log('Không thể kết xuất trang ${pageIndex + 1} qua máy chủ: $e');
      }
    }

    // If server upload hasn't been completed yet, try uploading in-memory bytes now:
    final bytes = _pdfBytes;
    if (uploadUri == null &&
        bytes != null &&
        bytes.isNotEmpty &&
        mapService != null) {
      try {
        final analysis = await mapService.analyzeDocument(
          fileName: state.fileName,
          bytes: bytes,
        );
        _documentMap = analysis.map;
        _uploadUri = analysis.uploadUri;
        uploadUri = analysis.uploadUri;
        state = state.copyWith(
          uploadUri: analysis.uploadUri,
          imageReviewAvailable: true,
          diagramPageCount: analysis.map.figurePages.length,
        );
        final image = await mapService.renderFigure(
          uploadUri: analysis.uploadUri,
          pageIndex: pageIndex,
        );
        if (image.isNotEmpty) return image;
      } catch (e) {
        _log('Không thể tải trang lên máy chủ để kết xuất: $e');
      }
    }

    // Client-side fallback (pdfx)
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final repository = ref.read(reviewRepositoryProvider);
        return await repository.renderPageForAudit(bytes, pageIndex);
      } catch (e) {
        _log('Không thể kết xuất trang ${pageIndex + 1} bằng bộ vẽ nội bộ: $e');
      }
    }
    return null;
  }

  VisionReviewService _visionService(DiagramAuditor auditor) {
    // Tight-crop rendering needs BOTH the server anatomy (bboxes) and the
    // upload ref (what /documents/render resolves); missing either one drops
    // to the legacy whole-page render — same audit, coarser image.
    final uploadUri = _uploadUri;
    final mapService = ref.read(documentMapServiceProvider);
    return VisionReviewService(
      auditor: auditor,
      documentMap: _documentMap,
      renderRegion: uploadUri == null || mapService == null
          ? null
          : (int pageIndex, List<double> bbox) async {
              final png = await mapService.renderFigure(
                uploadUri: uploadUri,
                pageIndex: pageIndex,
                bbox: bbox,
              );
              return base64Encode(png);
            },
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
  }

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

  /// Refreshes the landing card's short list ("Tiếp tục gần đây").
  ///
  /// Asks the store for the newest rows only — the card shows three titles and
  /// must not decode thirty payloads to render them. Failure is silent on
  /// purpose: the landing flow works without the card, so a store hiccup must
  /// not push an error banner over the steps the user is about to take.
  Future<void> _loadRecentSessions() async {
    try {
      final recent = await _store.listRecent(_recentSessionCount);
      if (!ref.mounted) return;
      state = state.copyWith(recentSessions: recent);
    } on Object {
      // See above: the shortcut is optional, the flow is not.
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
      _documentMap = null;
      _uploadUri = payload['uploadUri'] as String?;
      final pageTexts =
          (payload['pageTexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[];
      final projectInfo = _decodeProjectInfo(payload);
      state = state.copyWith(
        hasDocument: true,
        projectName: (payload['projectName'] as String?) ?? '',
        humanIssues: _decodeHumanIssues(payload),
        pageTexts: pageTexts,
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
        projectInfo: projectInfo,
        uploadUri: _uploadUri,
        imageReviewAvailable: _uploadUri != null && _uploadUri!.isNotEmpty,
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
      );
      // Recompute §F.3 against the restored pages, so a form payload lost to a
      // schema bump drops its findings together with the declaration that
      // justified them.
      _refreshProjectInfoFindings();
      // The opened session is now what the app is working on: a restart must
      // come back to THIS project container and declaration, not to whichever
      // one the draft was left over from. Awaited because this method is
      // already async and the lint (rightly) refuses a floating write.
      await _saveDraft();
      _scheduleToastClear();
      return true;
    } on Object catch (error) {
      state = state.copyWith(toast: 'Could not open review: $error');
      _scheduleToastClear();
      return false;
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      await _store.delete(id);
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Could not delete the saved review: $error',
      );
      return;
    }
    await loadHistory();
    await _loadRecentSessions();
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

  /// Word (.docx) twin — the format a supervisor actually opens, added
  /// 2026-09-25. Same inputs as the three siblings, and the honesty contract
  /// comes from the same [reportLimitations] list, so a caveat cannot be added
  /// to three exports out of four.
  Uint8List exportDocx() => buildDocxReport(
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
    humanIssues: state.humanIssues,
  );

  /// Writes the .docx to a file the user chooses. Bytes go through
  /// [ReportExporter.saveBytes] — a ZIP container must never be utf8-encoded.
  Future<String?> saveDocxReportToFile() => _exporter.saveBytes(
    fileName: _reportFileName(extension: 'docx'),
    bytes: exportDocx(),
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  );

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

  /// Reads the declared project info from a persisted payload.
  ///
  /// Degrades to null instead of throwing: a payload written by a future
  /// schema must cost the user their form, never their whole restored
  /// workspace — §F.3 then recomputes to nothing, which is coherent (no
  /// declaration, no declared-vs-cover claim).
  static ProjectInfo? _decodeProjectInfo(Map<String, dynamic> payload) {
    final raw = payload['projectInfo'] as Map<String, dynamic>?;
    if (raw == null) return null;
    try {
      return ProjectInfo.fromJson(raw);
    } on Object {
      return null;
    }
  }

  /// Reads reviewer-authored issues from a persisted payload.
  ///
  /// Degrades to an empty list instead of throwing: one future-schema row
  /// must cost the user that row, never the whole restored workspace.
  static List<HumanIssue> _decodeHumanIssues(Map<String, dynamic> payload) {
    final raw = payload['humanIssues'];
    if (raw is! List) return const [];
    try {
      return raw
          .map((entry) => HumanIssue.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  /// Persists what no run has claimed yet: the step-1 project container, the
  /// step-2 declaration and the reviewer's own issues.
  ///
  /// Deliberately small, and deliberately NOT the workspace. Units, findings,
  /// triage and the AI result all have a home the moment a run finishes (the
  /// saved session, reopened through History), and startup never auto-restores
  /// a previous workspace (decision 2026-09-23). Before this draft existed,
  /// the old `_saveSnapshot` re-encoded the whole workspace — units plus every
  /// page of text, ~1 MB on the OTES run — on each of a dozen mutations, for a
  /// reader that no longer existed. The draft is a few hundred bytes, written
  /// only when one of those three things actually changes.
  Future<void> _saveDraft() async {
    final payload = jsonEncode({
      'projectName': state.projectName,
      'projectInfo': state.projectInfo?.toJson(),
      'humanIssues': state.humanIssues
          .map((issue) => issue.toJson())
          .toList(growable: false),
    });
    try {
      await _store.saveDraft(payload);
    } on Object {
      // Persistence is best-effort: losing the draft never blocks a review.
    }
  }

  /// Reads the draft back into the landing flow (steps 1–2 pre-filled).
  ///
  /// Two guards, in this order: never clobber live state and never touch a
  /// disposed provider.
  ///
  /// "Live" means anything the user did before this read landed — a document
  /// loaded, or a step-1/step-2 field already typed (the read is a store hit,
  /// but it is still async, and overwriting a name typed in that window would
  /// be the same bug the old restore had to guard against).
  Future<void> _restoreDraft() async {
    try {
      final raw = await _store.loadDraft();
      if (!ref.mounted || raw == null || state.hasDocument) return;
      if (state.projectName.isNotEmpty ||
          state.projectInfo != null ||
          state.humanIssues.isNotEmpty) {
        return;
      }
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final name = (payload['projectName'] as String?)?.trim() ?? '';
      final info = _decodeProjectInfo(payload);
      final issues = _decodeHumanIssues(payload);
      if (name.isEmpty && info == null && issues.isEmpty) return;
      state = state.copyWith(
        projectName: name,
        projectInfo: info,
        clearProjectInfo: info == null,
        humanIssues: issues,
      );
      // §F.3 has no page texts to compare against before a document is loaded;
      // recomputing keeps the rule "findings always travel with the
      // declaration that justified them" true even on this path.
      _refreshProjectInfoFindings();
    } on Object {
      // A draft is a convenience, not a dependency: an unreadable one must
      // never block the app from starting.
    }
  }

  /// Returns false when the history write failed, so the caller does not
  /// claim "saved on this device" over an empty history: `setStringList` can
  /// refuse (storage full, a blocked web origin) and the old code reported
  /// success regardless, which made a finished run look like it vanished.
  Future<bool> _saveSession(WorkspaceReviewResult result) async {
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
      'uploadUri': _uploadUri ?? state.uploadUri,
      'pageTexts': state.pageTexts,
      // Same rule as the snapshot: findings derived from the declaration
      // travel with the declaration itself.
      'projectInfo': state.projectInfo?.toJson(),
      // The session's History row is grouped under this name — without it,
      // a finished run would fall into "Chưa gán project" after being
      // created inside a project.
      'projectName': state.projectName,
      // Same rule as the snapshot: the merged Report tab reads this list,
      // so the session must carry it too.
      'humanIssues': state.humanIssues
          .map((issue) => issue.toJson())
          .toList(growable: false),
    });
    try {
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
    } on Object catch (error) {
      state = state.copyWith(
        error: 'Review finished, but it could not be saved to history: $error',
      );
      return false;
    }
    await loadHistory();
    await _loadRecentSessions();
    return true;
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
