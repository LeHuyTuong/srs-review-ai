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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../models/srs_document.dart';
import '../parsing/requirement_splitter.dart';

abstract interface class DocumentParser {
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  });
}

class ParseService implements DocumentParser {
  ParseService({RequirementSplitter splitter = const RequirementSplitter()})
    : _pdf = PdfParser(splitter),
      _docx = DocxParser(splitter);

  final PdfParser _pdf;
  final DocxParser _docx;

  @override
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  }) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'pdf' => _pdf.parse(fileName: fileName, bytes: bytes, onStatus: onStatus),
      'docx' => _docx.parse(
        fileName: fileName,
        bytes: bytes,
        onStatus: onStatus,
      ),
      // Legacy binary .doc cannot be unzipped; refuse early with a clear reason
      // rather than producing an empty document (research 06).
      'doc' => throw ParseException(
        'Legacy .doc files are not supported. Save the file as .docx or PDF and try again.',
      ),
      _ => throw ParseException(
        'Unsupported file type ".$extension". Choose a PDF or DOCX file.',
      ),
    };
  }
}

class PdfParser implements DocumentParser {
  const PdfParser(this._splitter);

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
    } on Exception catch (error) {
      throw ParseException(
        'Could not open the PDF (it may be corrupted or password protected): $error',
      );
    }

    try {
      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final pageTexts = <String>[];
      for (var page = 0; page < pageCount; page++) {
        // Large PDFs spend real seconds in text extraction; report per-page
        // progress (throttled to multi-page documents) so the UI shows life.
        if (onStatus != null && pageCount >= 8) {
          onStatus('Extracting text (page ${page + 1}/$pageCount)…');
          await Future<void>.delayed(Duration.zero);
        }
        pageTexts.add(
          extractor.extractText(startPageIndex: page, endPageIndex: page),
        );
      }

      if (pageTexts.every((text) => text.trim().isEmpty)) {
        throw ParseException(
          'This PDF has no text layer — it looks like a scan. OCR is out of scope; '
          'please upload the original PDF exported from Word.',
          isScannedPdf: true,
        );
      }

      return SrsDocument(
        fileName: fileName,
        pageCount: pageTexts.length,
        pageTexts: pageTexts,
        requirements: _splitter.split(pageTexts),
        imagePageIndexes: _detectImagePages(pageTexts),
      );
    } finally {
      document.dispose();
    }
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
