/// Shared plumbing for the workspace use-case controllers.
///
/// A controller is a plain Dart object — no widgets, no providers of its own —
/// holding one reference to the notifier whose session it works on. Riverpod
/// marks `Notifier.ref` and `Notifier.state` `@protected` precisely so only the
/// notifier touches them, so the notifier hands them over through
/// [WorkspaceViewModel.workspaceRef] and `.workspaceState`.
///
/// Everything else here exists so a use case could move between files without
/// its body changing: the session-transient document handles, the execution log
/// and the toast timer stay on the notifier, and a helper owned by a sibling
/// controller is reached through that controller's instance.
part of '../workspace_view_model.dart';

abstract base class WorkspaceController {
  WorkspaceController(this.vm);

  /// The workspace session this controller reads and mutates.
  final WorkspaceViewModel vm;

  /// The Riverpod `Ref` of the notifier, for the providers a use case needs.
  Ref get ref => vm.workspaceRef;

  WorkspaceState get state => vm.workspaceState;

  set state(WorkspaceState next) => vm.workspaceState = next;

  // ---- session-transient document handles (owned by the notifier) ----------

  /// The parsed document of the current import. Null after a session is opened
  /// from History, where only the state (units, findings) survived.
  SrsDocument? get _document => vm._document;

  set _document(SrsDocument? value) => vm._document = value;

  /// The original bytes, in memory for the renderer. Never persisted.
  Uint8List? get _pdfBytes => vm._pdfBytes;

  set _pdfBytes(Uint8List? value) => vm._pdfBytes = value;

  /// Server-side anatomy of the current import (`/documents/analyze`) and the
  /// `upload://` ref that render calls need.
  DocumentMap? get _documentMap => vm._documentMap;

  set _documentMap(DocumentMap? value) => vm._documentMap = value;

  String? get _uploadUri => vm._uploadUri;

  set _uploadUri(String? value) => vm._uploadUri = value;

  SessionStore get _store => vm._store;

  // ---- writers the notifier owns ------------------------------------------

  void _log(String message) => vm._log(message);

  void _scheduleToastClear() => vm._scheduleToastClear();

  // ---- use cases owned by a sibling controller ----------------------------

  /// The project-info findings are recomputed after anything that can change
  /// the project container — an import, an opened session, an edit.
  void _refreshProjectInfoFindings() => vm._draft._refreshProjectInfoFindings();

  Future<void> _saveDraft() => vm._draft._saveDraft();

  /// Persists one finished run. Owned by History: the run controller reports it,
  /// the history controller writes it.
  Future<bool> _saveSession(WorkspaceReviewResult result) =>
      vm._history._saveSession(result);
}
