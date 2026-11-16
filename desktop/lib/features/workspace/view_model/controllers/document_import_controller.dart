/// Getting a document in: the bundled demo, a picked PDF/DOCX, the server's
/// blueprint analysis, and the unit inventory that import produces.
///
/// Everything that touches the parser lives behind this controller, so a view
/// never sees a `SrsDocument` or a page index it did not get from the state.
part of '../workspace_view_model.dart';

final class DocumentImportController extends WorkspaceController {
  DocumentImportController(super.vm);

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
}
