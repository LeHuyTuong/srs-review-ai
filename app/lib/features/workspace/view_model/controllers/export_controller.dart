/// Reports out: Markdown, JSON, HTML, DOCX, the file-name convention and the
/// share link.
///
/// The builders themselves live in `report_export/`; this controller only
/// feeds them the current state and writes the file.
part of '../workspace_view_model.dart';

final class ExportController extends WorkspaceController {
  ExportController(super.vm);

  /// Stateless and platform-delegating, so it needs no provider: constructing
  /// it inline keeps the ViewModel constructible in tests that only care about
  /// review behaviour.
  static const ReportExporter _exporter = ReportExporter();

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

  /// Switch the language of every exported report, markdown preview included.
  /// One setter rather than four, because the four exports are twins: letting
  /// them carry different languages is exactly the mixing this feature exists
  /// to remove.
  void setReportLanguage(ReportLanguage language) {
    if (state.reportLanguage == language) return;
    state = state.copyWith(reportLanguage: language);
    // Fire-and-forget, same contract as the step-1/2 setters: the choice is a
    // preference with no other home, so without the draft a restart resets it
    // to Vietnamese under a user who already picked English.
    _saveDraft();
  }

  String exportMarkdown() => buildMarkdownReport(
    fileName: state.fileName,
    language: state.reportLanguage,
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
    return _exporter.save(fileName: reportFileName(), contents: report);
  }

  /// Structured twin of [exportMarkdown] — same inputs, same numbers, one
  /// shared schema for a server or web tool (goal §4 Output row).
  String exportJson() => const JsonEncoder.withIndent('  ').convert(
    buildJsonReport(
      fileName: state.fileName,
      language: state.reportLanguage,
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
      fileName: reportFileName(extension: 'json'),
      contents: report,
    );
  }

  /// Dashboard twin of [exportMarkdown] — the brief's Report row asks for a
  /// dashboard a supervisor opens in a browser, not just prose for a repo.
  /// Same inputs as both twins; the numbers agree by construction.
  String exportHtml() => buildHtmlReport(
    fileName: state.fileName,
    language: state.reportLanguage,
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
      fileName: reportFileName(extension: 'html'),
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
    language: state.reportLanguage,
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
    fileName: reportFileName(extension: 'docx'),
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
      _exporter.share(fileName: reportFileName(), contents: exportMarkdown());

  /// The name every save path writes, and the one the share sheet shows.
  ///
  /// Public because it is user-visible behaviour, not an internal detail: the
  /// report language rides in the name so that exporting both an English and a
  /// Vietnamese copy of one run produces two files instead of one silently
  /// overwriting the other in the Downloads folder.
  String reportFileName({String extension = 'md'}) {
    final base = state.fileName.trim().isEmpty ? 'srs' : state.fileName;
    final stem = base.contains('.')
        ? base.substring(0, base.lastIndexOf('.'))
        : base;
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    // The language rides in the file name: a team exporting both an English
    // and a Vietnamese copy of one run gets two files, not one that silently
    // overwrites the other in the Downloads folder.
    return 'srs-review-$safe-${state.reportLanguage.wire}-$stamp.$extension';
  }
}
