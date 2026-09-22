/// PDF/DOCX -> [SrsDocument]. Client-side, one pass, no OCR (decision D5).
///
/// Verified against the installed packages on 2026-09-09:
///   * syncfusion_flutter_pdf 34.2.7 exposes extractText / extractTextLines /
///     findText — but NO image-extraction API (unlike the .NET build). Pages
///     that hold diagrams are therefore inferred from text density; see
///     [PdfParser._detectImagePages].
///   * archive 4.2.0: ArchiveFile.readBytes() is the supported accessor.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../models/srs_document.dart';
import '../parsing/blueprint_builder.dart';
import '../parsing/requirement_splitter.dart';
import '../parsing/table_of_contents.dart';

abstract interface class DocumentParser {
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  });
}

/// One parse request, packaged for the background isolate.
///
/// Plain values only: the whole object is copied across the isolate boundary.
class _ParseJob {
  const _ParseJob(this.fileName, this.bytes, this.splitter);

  final String fileName;
  final Uint8List bytes;
  final RequirementSplitter splitter;
}

/// Top-level so it can be handed to [compute]. Runs OFF the UI isolate.
Future<SrsDocument> _parseEntry(_ParseJob job) {
  final extension = _extensionOf(job.fileName);
  return switch (extension) {
    'pdf' => PdfParser(
      job.splitter,
    ).parse(fileName: job.fileName, bytes: job.bytes),
    'docx' => DocxParser(
      job.splitter,
    ).parse(fileName: job.fileName, bytes: job.bytes),
    _ => throw ParseException(
      'Unsupported file type ".$extension". Choose a PDF or DOCX file.',
    ),
  };
}

String _extensionOf(String fileName) => fileName.split('.').last.toLowerCase();

class ParseService implements DocumentParser {
  ParseService({RequirementSplitter splitter = const RequirementSplitter()})
    // Named initializing formals cannot target a private field, so this
    // assignment has to stay explicit.
    // ignore: prefer_initializing_formals
    : _splitter = splitter;

  final RequirementSplitter _splitter;

  @override
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  }) {
    final extension = _extensionOf(fileName);
    // Cheap refusals stay on the calling isolate: there is no point spawning a
    // background one just to reject a file we can rule out from its name.
    if (extension == 'doc') {
      // Legacy binary .doc cannot be unzipped; refuse early with a clear reason
      // rather than producing an empty document (research 06).
      throw ParseException(
        'Legacy .doc files are not supported. Save the file as .docx or PDF and try again.',
      );
    }
    if (!kSupportedDocumentExtensions.contains(extension)) {
      throw ParseException(
        'Unsupported file type ".$extension". Choose a PDF or DOCX file.',
      );
    }

    // Parsing is CPU-bound: a 28 MB / 300-page SRS blocks the UI thread for
    // seconds on a phone and the OS may kill the app. `compute` runs the work
    // on a background isolate. Web has no isolates, so there `compute` invokes
    // the callback inline — Chrome behaves exactly as it did before.
    //
    // Trade-off: per-page progress cannot cross the isolate boundary, so this
    // status is coarser than the old page counter. The import UI keeps an
    // animated spinner and a live elapsed timer, so a long parse still reads as
    // "working" rather than "hung".
    onStatus?.call('Parsing $fileName…');
    return compute(_parseEntry, _ParseJob(fileName, bytes, _splitter));
  }
}

class PdfParser implements DocumentParser {
  const PdfParser(this._splitter);

  /// Maximum number of pages accepted from a PDF. This is a generic parser
  /// safeguard, not a document-specific scope rule, and is checked before
  /// extracting page text.
  static const int maxPageCount = 300;

  /// A page with fewer characters than this, in a document that has real text
  /// elsewhere, is treated as a diagram/mockup page.
  static const int _diagramPageTextThreshold = 120;

  final RequirementSplitter _splitter;

  @override
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  }) async {
    late final PdfDocument document;
    try {
      document = PdfDocument(inputBytes: bytes);
    } on Object catch (error) {
      // `on Exception` was not enough. A truncated or zero-byte PDF makes
      // Syncfusion throw ArgumentError, which is an *Error*, not an Exception
      // — so it sailed straight past this handler and crashed the import
      // instead of showing the user a reason. Measured with a 0-byte file and
      // a valid-header/garbage-body file: both threw ArgumentError.
      throw ParseException(
        'Could not open the PDF (it may be corrupted, empty or password '
        'protected): $error',
      );
    }

    try {
      final pageCount = document.pages.count;
      if (pageCount > maxPageCount) {
        throw ParseException(
          'This PDF has $pageCount pages. The limit is $maxPageCount pages.',
        );
      }
      final extractor = PdfTextExtractor(document);
      final pageTexts = <String>[];
      for (var page = 0; page < pageCount; page++) {
        // Large PDFs spend real seconds in text extraction; report per-page
        // progress (throttled to multi-page documents) so the UI shows life.
        if (onStatus != null && pageCount >= 8) {
          onStatus('Extracting text (page ${page + 1}/$pageCount)…');
          await Future<void>.delayed(Duration.zero);
        }
        pageTexts.add(_extractPageText(extractor, page));
      }

      if (pageTexts.every((text) => text.trim().isEmpty)) {
        throw ParseException(
          'This PDF has no text layer — it looks like a scan. OCR is out of scope; '
          'please upload the original PDF exported from Word.',
          isScannedPdf: true,
        );
      }

      // Parsed once: the splitter needs the index to pick its strategy, and the
      // blueprint keeps it (chapter ranges, artifact pages) for every later
      // pass — vision targeting, index checks, the section tree in the UI.
      final toc = TableOfContents.parse(pageTexts);

      return SrsDocument(
        fileName: fileName,
        pageCount: pageTexts.length,
        pageTexts: pageTexts,
        requirements: _splitter.split(pageTexts, toc: toc),
        imagePageIndexes: _detectImagePages(pageTexts),
        blueprint: const BlueprintBuilder().build(
          pageTexts: pageTexts,
          toc: toc,
        ),
      );
    } finally {
      document.dispose();
    }
  }

  /// Two text runs whose tops differ by at most this many pixels are the same
  /// visual row. Word's PDF export splits one printed line into several runs
  /// whose baselines differ by a pixel or two (the OTES report puts a
  /// heading's number at top=93 and its title at top=92).
  static const double _sameRowTolerance = 3;

  /// Rebuilds a page's text from `extractTextLines` instead of `extractText`.
  ///
  /// Why: on Word-exported PDFs `extractText` emits **one word per line**
  /// (measured on the 217-page OTES report: every body page averages 1.0
  /// words/line, so `3.3 Availability` arrives as `3.3` / `Availability` on
  /// separate lines). Every downstream pattern — `_sectionHeading`, modal
  /// sentences, numbered use-case steps — expects real lines, so with the raw
  /// extraction the entire prose of the document was invisible and only the
  /// TOC-driven use-case tables survived. Grouping the extractor's text lines
  /// by vertical position restores real lines ("3.3 Availability",
  /// "● The system must be available at any time 24/7").
  static String _extractPageText(PdfTextExtractor extractor, int page) {
    final lines = extractor.extractTextLines(
      startPageIndex: page,
      endPageIndex: page,
    );
    if (lines.isEmpty) {
      return stripPageNumberFooters(
        extractor.extractText(startPageIndex: page, endPageIndex: page),
      );
    }
    final text = joinVisualLines([
      for (final line in lines)
        (top: line.bounds.top, left: line.bounds.left, text: line.text.trim()),
    ]);
    return stripPageNumberFooters(text);
  }

  /// Removes PDF footer rows such as `Page | 1 4 Page | 1 5` before the
  /// requirement splitter sees them. These rows are extraction noise, not
  /// requirements; leaving them in an open section can create a review unit
  /// containing only page numbers.
  @visibleForTesting
  static String stripPageNumberFooters(String text) {
    final lines = text.split('\n');
    final pageWord = RegExp(r'page', caseSensitive: false);
    final digits = RegExp(r'\d');
    return lines
        .where((line) {
          final normalized = line.trim();
          if (!pageWord.hasMatch(normalized) || !digits.hasMatch(normalized)) {
            return true;
          }
          final remainder = normalized
              .replaceAll(pageWord, '')
              .replaceAll(RegExp(r'[0-9|:/\\\s-]'), '');
          return remainder.isNotEmpty;
        })
        .join('\n');
  }

  /// Groups text runs into visual rows (same `top` within
  /// [_sameRowTolerance]), orders rows top-to-bottom and runs inside a row
  /// left-to-right, then joins runs with a single space and rows with a
  /// newline. Pure function so the regrouping is unit-testable without a PDF.
  @visibleForTesting
  static String joinVisualLines(
    List<({double top, double left, String text})> runs,
  ) {
    final sorted = [...runs]
      ..sort((a, b) {
        final byTop = a.top.compareTo(b.top);
        return byTop != 0 ? byTop : a.left.compareTo(b.left);
      });
    final rows = <List<({double left, String text})>>[];
    var rowTop = double.nan;
    for (final run in sorted) {
      if (run.text.isEmpty) continue;
      if (rows.isEmpty || (run.top - rowTop).abs() > _sameRowTolerance) {
        rows.add([(left: run.left, text: run.text)]);
        rowTop = run.top;
      } else {
        rows.last.add((left: run.left, text: run.text));
      }
    }
    return rows
        .map(
          (row) => (row..sort((a, b) => a.left.compareTo(b.left)))
              .map((run) => run.text)
              .join(' '),
        )
        .join('\n');
  }

  /// Heuristic stand-in for real image extraction (the package has no API for
  /// it). Pages that are nearly text-free inside an otherwise text-rich
  /// document are almost always a use case diagram, ERD or UI mockup.
  static List<int> _detectImagePages(List<String> pageTexts) {
    final hasRealText = pageTexts.any(
      (t) => t.trim().length >= _diagramPageTextThreshold,
    );
    if (!hasRealText) return const [];
    final pages = <int>[];
    for (var i = 0; i < pageTexts.length; i++) {
      final length = pageTexts[i].trim().length;
      if (length > 0 && length < _diagramPageTextThreshold) pages.add(i);
    }
    return pages;
  }
}

class DocxParser implements DocumentParser {
  const DocxParser(this._splitter);

  static const String _documentEntry = 'word/document.xml';
  static const String _mediaPrefix = 'word/media/';

  final RequirementSplitter _splitter;

  @override
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  }) async {
    late final Archive archive;
    // Yield before the blocking decode so the progress frame can paint.
    onStatus?.call('Opening DOCX archive…');
    await Future<void>.delayed(Duration.zero);
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Exception catch (error) {
      throw ParseException('Could not read the DOCX archive: $error');
    }

    final entry = archive.findFile(_documentEntry);
    if (entry == null) {
      throw ParseException(
        'Not a valid DOCX file: $_documentEntry is missing.',
      );
    }

    final xmlBytes = entry.readBytes();
    if (xmlBytes == null || xmlBytes.isEmpty) {
      throw ParseException('The DOCX body is empty.');
    }

    onStatus?.call('Extracting text…');
    await Future<void>.delayed(Duration.zero);
    final text = extractText(utf8.decode(xmlBytes, allowMalformed: true));
    if (text.trim().isEmpty) {
      throw ParseException('No text found in the DOCX file.');
    }

    final hasMedia = archive.files.any((f) => f.name.startsWith(_mediaPrefix));

    // DOCX has no page concept before rendering: one logical page.
    onStatus?.call('Detecting requirements…');
    await Future<void>.delayed(Duration.zero);
    return SrsDocument(
      fileName: fileName,
      pageCount: 1,
      pageTexts: [text],
      requirements: _splitter.split([text]),
      imagePageIndexes: hasMedia ? const [0] : const [],
    );
  }

  /// `w:p` -> line, `w:t` -> text, `w:tab` -> tab. Exposed for unit tests.
  static String extractText(String documentXml) {
    final document = XmlDocument.parse(documentXml);
    final lines = <String>[];
    // `namespaceUri: '*'` matches the w: prefix without hardcoding the WordML
    // namespace URI (`namespace:` is deprecated in xml 7).
    for (final paragraph in document.findAllElements('p', namespaceUri: '*')) {
      final buffer = StringBuffer();
      for (final node in paragraph.descendantElements) {
        switch (node.name.local) {
          case 't':
            buffer.write(node.innerText);
          case 'tab':
            buffer.write('\t');
          case 'br':
            buffer.write('\n');
        }
      }
      final line = buffer.toString().trim();
      if (line.isNotEmpty) lines.add(line);
    }
    return lines.join('\n');
  }
}
