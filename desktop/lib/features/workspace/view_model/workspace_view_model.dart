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
import '../../../deterministic_checks/checks/blueprint_checks.dart';
import '../../../deterministic_checks/checks/format_layout_checks.dart';
import '../../../deterministic_checks/checks/project_info_checks.dart';
import '../../../deterministic_checks/checks/reference_checks.dart';
import '../../../deterministic_checks/checks/rubric_config.dart';
import '../../../deterministic_checks/checks/syllabus_checks.dart';
import '../../../deterministic_checks/models/deterministic_finding.dart';
import '../../../deterministic_checks/verifier.dart';
import '../../../diagram_audit/models/document_map.dart';
import '../../../diagram_audit/services/vision_review_service.dart';
import '../../../document_import/models/project_info.dart';
import '../../../document_import/models/srs_document.dart';
import '../../../document_import/models/workspace_unit.dart';
import '../../../report_export/docx_report.dart';
import '../../../report_export/html_report.dart';
import '../../../report_export/report_export.dart';
import '../../../report_export/report_exporter.dart';
import '../../../requirement_review/models/human_issue.dart';
import '../../../requirement_review/models/report_language.dart';
import '../../../requirement_review/models/review_models.dart' show Severity;
import '../../../requirement_review/models/review_progress.dart';
import '../../../requirement_review/models/workspace_findings.dart';
import '../../../review_history/services/session_store.dart';
import '../models/ask_document.dart';
import '../models/demo_units.dart';

/// Views need the SavedSession shape to render history rows; they reach it
/// through the ViewModel layer, never by importing data/services directly.
export '../../../review_history/services/session_store.dart' show SavedSession;

part 'controllers/ask_controller.dart';
part 'controllers/diagram_audit_controller.dart';
part 'controllers/document_import_controller.dart';
part 'controllers/export_controller.dart';
part 'controllers/history_controller.dart';
part 'controllers/project_draft_controller.dart';
part 'controllers/review_run_controller.dart';
part 'controllers/workspace_controller.dart';

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
    this.reportLanguage = ReportLanguage.vietnamese,
  });

  /// The language every exported report is written in (2026-09-25).
  ///
  /// A saved preference, carried by the workspace draft: the first cut kept it
  /// session-only and the choice reset to Vietnamese on every restart — a team
  /// that reports in English re-picked the switch on every launch. Vietnamese
  /// stays the default (the app's UI is Vietnamese and the documents under
  /// review are Vietnamese capstone reports); switching is one tap in the
  /// export modal and applies to all four formats at once.
  ///
  /// Still deliberately NOT in the session payload: a saved review is the
  /// evidence, and the language of a report is how it was rendered, not part of
  /// what was measured — restoring a session must not silently change the
  /// language of the next export.
  final ReportLanguage reportLanguage;

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
    ReportLanguage? reportLanguage,
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
    reportLanguage: reportLanguage ?? this.reportLanguage,
  );
}

/// The workspace session: the state, and the façade the views talk to.
///
/// One controller per use case lives in `controllers/` — project draft,
/// document import, review run, history, export, ask — and every public member
/// below forwards to the one that owns it. Views and tests keep a single entry
/// point while the logic sits behind a named boundary; what is left here is the
/// state class, the shared session handles, the execution log and the two
/// cross-cutting writers (units, toast).
class WorkspaceViewModel extends Notifier<WorkspaceState> {
  /// The document handles are shared: import fills them, review renders from
  /// them, history clears them. Controllers reach them through
  /// [WorkspaceController].
  SrsDocument? _document;
  Uint8List? _pdfBytes;

  /// Server-side anatomy of the CURRENT import (`/documents/analyze`) and the
  /// `upload://` ref render calls need. Both are session-transient like
  /// [_pdfBytes]: a session opened from History has no bytes on the server
  /// either, so the vision audit falls back to the heuristic path there —
  /// exactly like it does when the analyze call fails.
  DocumentMap? _documentMap;
  String? _uploadUri;
  Timer? _toastTimer;
  SessionStore get _store => ref.read(sessionStoreProvider);

  /// The use-case controllers. `late final` because Riverpod constructs this
  /// object itself; each controller is built on first use.
  late final ProjectDraftController _draft = ProjectDraftController(this);
  late final DocumentImportController _import = DocumentImportController(this);
  late final ReviewRunController _review = ReviewRunController(this);
  late final DiagramAuditController _diagrams = DiagramAuditController(this);
  late final HistoryController _history = HistoryController(this);
  late final ExportController _export = ExportController(this);
  late final AskController _ask = AskController(this);

  // ------------------------------------------------- the controllers' seam

  /// The notifier's `Ref`, for the controllers.
  Ref get workspaceRef => ref;

  /// The session the controllers read and write. Two accessors instead of a
  /// wide interface: the controllers are the same layer as this notifier, they
  /// just are not notifiers themselves.
  WorkspaceState get workspaceState => state;
  set workspaceState(WorkspaceState next) => state = next;

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _review._subscription?.cancel();
      _toastTimer?.cancel();
      _review._elapsedTimer?.cancel();
    });
    // No auto-restore of a previous workspace on startup (decision
    // 2026-09-23): opening the app must land on the guided first-run flow
    // (Bước 1→3), never inside the previous session. Saved runs stay reachable
    // via History (openSession), which carries units, findings, triage and the
    // declaration on its own.
    //
    // Two small things ARE restored, because a restart used to throw them
    // away and nobody asked for that: the DRAFT (the project container, the
    // declaration the user typed in steps 1–2, and the report-language
    // preference) and the landing card's short list of recent sessions.
    scheduleMicrotask(_draft._restoreDraft);
    scheduleMicrotask(_history._loadRecentSessions);
    return const WorkspaceState();
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

  /// Delegates to [ProjectDraftController.setProjectInfo].
  void setProjectInfo(ProjectInfo info) => _draft.setProjectInfo(info);

  /// Delegates to [ProjectDraftController.createProject].
  void createProject(String name) => _draft.createProject(name);

  /// Delegates to [ProjectDraftController.addHumanIssue].
  void addHumanIssue({
    required String title,
    String detail = '',
    Severity severity = Severity.medium,
    String? section,
  }) => _draft.addHumanIssue(
    title: title,
    detail: detail,
    severity: severity,
    section: section,
  );

  /// Delegates to [ProjectDraftController.removeHumanIssue].
  void removeHumanIssue(String id) => _draft.removeHumanIssue(id);

  // ------------------------------------------------------------- demo / import

  /// Delegates to [DocumentImportController.loadDemo].
  Future<void> loadDemo() => _import.loadDemo();

  /// Delegates to [DocumentImportController.importDocument].
  Future<void> importDocument() => _import.importDocument();

  // ------------------------------------------------------------- units

  /// Delegates to [DocumentImportController.classifyUnit].
  void classifyUnit(String key, UnitKind kind) =>
      _import.classifyUnit(key, kind);

  /// Delegates to [DocumentImportController.setUnitSelected].
  void setUnitSelected(String key, bool selected) =>
      _import.setUnitSelected(key, selected);

  /// Delegates to [DocumentImportController.setSelectedAll].
  void setSelectedAll(Set<String> keys, bool selected) =>
      _import.setSelectedAll(keys, selected);

  /// Delegates to [ReviewRunController.setFindingStatus].
  void setFindingStatus(String findingId, FindingStatus status) =>
      _review.setFindingStatus(findingId, status);

  /// Delegates to [ReviewRunController.verifyStatuses].
  VerifyDiff verifyStatuses() => _review.verifyStatuses();

  /// Identity test on a `Map<String, FindingStatus>` — true when both
  // maps hold the same key→status pairs. Used by [verifyStatuses] to
  // skip a no-op write.

  // ------------------------------------------------------------- review

  /// Delegates to [ReviewRunController.runReview].
  Future<void> runReview() => _review.runReview();

  /// Delegates to [DiagramAuditController.diagramAuditCount].
  int get diagramAuditCount => _diagrams.diagramAuditCount;

  /// Delegates to [DiagramAuditController.canAuditDiagrams].
  bool get canAuditDiagrams => _diagrams.canAuditDiagrams;

  /// Delegates to [DiagramAuditController.hasPdfBytes].
  bool get hasPdfBytes => _diagrams.hasPdfBytes;

  /// Delegates to [DiagramAuditController.needsReImport].
  bool get needsReImport => _diagrams.needsReImport;

  /// Delegates to [DiagramAuditController.canRenderPdf].
  bool get canRenderPdf => _diagrams.canRenderPdf;

  /// Delegates to [DiagramAuditController.renderPageImage].
  Future<Uint8List?> renderPageImage(int pageIndex) =>
      _diagrams.renderPageImage(pageIndex);

  /// Delegates to [DiagramAuditController.auditDiagrams].
  Future<void> auditDiagrams() => _diagrams.auditDiagrams();

  /// Delegates to [ExportController.canShareReport].
  bool get canShareReport => _export.canShareReport;

  /// Delegates to [ExportController.mintShareLink].
  Future<String?> mintShareLink() => _export.mintShareLink();

  /// Delegates to [ReviewRunController.cancelReview].
  void cancelReview() => _review.cancelReview();

  /// Delegates to [ReviewRunController.dismissRunSummary].
  void dismissRunSummary() => _review.dismissRunSummary();

  /// Delegates to [ReviewRunController.dismissError].
  void dismissError() => _review.dismissError();

  // ------------------------------------------------------------- ask

  /// Delegates to [AskController.askDocument].
  List<WorkspaceUnit> askDocument(String question) =>
      _ask.askDocument(question);

  /// Delegates to [AskController.askQuestion].
  Future<AskOutcome> askQuestion(String question) => _ask.askQuestion(question);

  // ------------------------------------------------------------- history

  /// Delegates to [HistoryController.loadHistory].
  Future<void> loadHistory() => _history.loadHistory();

  /// Delegates to [HistoryController.openSession].
  Future<bool> openSession(String id) => _history.openSession(id);

  /// Delegates to [HistoryController.deleteSession].
  Future<void> deleteSession(String id) => _history.deleteSession(id);

  // ------------------------------------------------------------- export

  /// Delegates to [ExportController.setReportLanguage].
  void setReportLanguage(ReportLanguage language) =>
      _export.setReportLanguage(language);

  /// Delegates to [ExportController.exportMarkdown].
  String exportMarkdown() => _export.exportMarkdown();

  /// Delegates to [ExportController.saveReportToFile].
  Future<String?> saveReportToFile() => _export.saveReportToFile();

  /// Delegates to [ExportController.exportJson].
  String exportJson() => _export.exportJson();

  /// Delegates to [ExportController.saveJsonReportToFile].
  Future<String?> saveJsonReportToFile() => _export.saveJsonReportToFile();

  /// Delegates to [ExportController.exportHtml].
  String exportHtml() => _export.exportHtml();

  /// Delegates to [ExportController.saveHtmlReportToFile].
  Future<String?> saveHtmlReportToFile() => _export.saveHtmlReportToFile();

  /// Delegates to [ExportController.exportDocx].
  Uint8List exportDocx() => _export.exportDocx();

  /// Delegates to [ExportController.saveDocxReportToFile].
  Future<String?> saveDocxReportToFile() => _export.saveDocxReportToFile();

  /// Delegates to [ExportController.shareReport].
  Future<String> shareReport() => _export.shareReport();

  /// Delegates to [ExportController.reportFileName].
  String reportFileName({String extension = 'md'}) =>
      _export.reportFileName(extension: extension);

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
