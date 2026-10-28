/// Saved runs: the History tab's list, the landing card's short list of recent
/// sessions, opening a session back into the workspace, and deleting one.
///
/// Persistence goes through the `SessionStore` interface only.
part of '../workspace_view_model.dart';

final class HistoryController extends WorkspaceController {
  HistoryController(super.vm);

  /// How many saved runs the landing card offers. Three is a shortcut back
  /// into the most recent submission round, not a second History tab.
  static const int _recentSessionCount = 3;

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

  @override
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
