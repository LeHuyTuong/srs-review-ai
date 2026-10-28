/// The diagram half of a review: whether there is an audit at all, which pages
/// the vision pass sees, and rendering one page back to an image.
///
/// Separate from [ReviewRunController] because the two never call each other:
/// the run controller runs the text review over the units, this one owns the
/// pages (`/documents/render`, `upload://` refs) and the auditor wiring. A host
/// without a PDF renderer is what the `rendererUnavailable` flags in the state
/// record — never a silent text-only pass.
part of '../workspace_view_model.dart';

final class DiagramAuditController extends WorkspaceController {
  DiagramAuditController(super.vm);

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
}
