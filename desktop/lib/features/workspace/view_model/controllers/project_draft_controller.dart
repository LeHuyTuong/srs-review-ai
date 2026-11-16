/// The project container the user fills in during steps 1-2: its name, the
/// project-info form, the reviewer's own issues, and the small draft that
/// survives a restart.
///
/// Deliberately NOT the home of units, findings or results — those belong to a
/// saved session and reopen through History (decision 2026-09-23).
part of '../workspace_view_model.dart';

final class ProjectDraftController extends WorkspaceController {
  ProjectDraftController(super.vm);

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

  @override
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

  @override
  Future<void> _saveDraft() async {
    final payload = jsonEncode({
      'projectName': state.projectName,
      'projectInfo': state.projectInfo?.toJson(),
      'humanIssues': state.humanIssues
          .map((issue) => issue.toJson())
          .toList(growable: false),
      'reportLanguage': state.reportLanguage.wire,
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
      // The language is a preference, not step-1/2 work, so it is applied
      // BEFORE the typed-fields guard below: a name typed in the read window
      // must not cost the choice. A draft that predates the field (key absent)
      // is a no-op — mapping absence through `fromWire` would write Vietnamese
      // over a language the user already picked. The one input that can lose
      // here is a Vietnamese choice made inside the same read window as a draft
      // that carries 'en'; it falls back to the app default, not to another
      // language.
      final language = _decodeReportLanguage(payload);
      if (language != null) {
        state = state.copyWith(reportLanguage: language);
      }
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
}

/// Reads the declared project info from a persisted payload.
///
/// Degrades to null instead of throwing: a payload written by a future
/// schema must cost the user their form, never their whole restored
/// workspace — §F.3 then recomputes to nothing, which is coherent (no
/// declaration, no declared-vs-cover claim).
ProjectInfo? _decodeProjectInfo(Map<String, dynamic> payload) {
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
List<HumanIssue> _decodeHumanIssues(Map<String, dynamic> payload) {
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

/// Reads the report-language preference from a persisted payload.
///
/// Null — never a silent Vietnamese — when the key is absent or malformed:
/// absence is a draft written before the field existed, and mapping it
/// through `fromWire` would push the default over a language the user
/// already picked. A value that IS present but unreadable falls back to the
/// app default through [ReportLanguage.fromWire] rather than crashing a
/// startup over a preference.
ReportLanguage? _decodeReportLanguage(Map<String, dynamic> payload) {
  final wire = payload['reportLanguage'];
  if (wire is! String || wire.isEmpty) return null;
  return ReportLanguage.fromWire(wire);
}
