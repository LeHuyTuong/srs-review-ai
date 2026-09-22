/// End-to-end coverage for [ParseService].
///
/// This is the only test that drives a real parse, and it exists because the
/// implementation now hands the work to a background isolate via `compute`:
/// the cheap validation paths throw on the calling isolate, while a genuine
/// parse failure has to cross the isolate boundary and still arrive as a
/// [ParseException] — an assumption worth pinning down rather than trusting.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

const String _wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// The smallest DOCX [DocxParser] accepts: a zip holding `word/document.xml`.
Uint8List _minimalDocx(List<String> paragraphs) {
  final body = paragraphs
      .map((text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>')
      .join();
  final xml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="$_wordNamespace"><w:body>$body</w:body></w:document>';
  final bytes = utf8.encode(xml);
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('ParseService', () {
    test('parses a DOCX off the calling isolate', () async {
      final document = await ParseService().parse(
        fileName: 'spec.docx',
        bytes: _minimalDocx([
          'FR-01 The system shall store each submitted report.',
        ]),
      );

      expect(document.fileName, 'spec.docx');
      expect(document.requirements.map((r) => r.id), contains('FR-01'));
    });

    test('a failure raised inside the isolate still arrives typed', () async {
      // Valid zip, valid document.xml, but no readable text — so the throw
      // happens deep inside the parser, on the other side of the isolate.
      await expectLater(
        ParseService().parse(
          fileName: 'empty.docx',
          bytes: _minimalDocx(const []),
        ),
        throwsA(
          isA<ParseException>().having(
            (error) => error.message,
            'message',
            contains('No text found'),
          ),
        ),
      );
    });

    test('refuses a legacy .doc before spawning anything', () {
      expect(
        () => ParseService().parse(fileName: 'old.doc', bytes: Uint8List(0)),
        throwsA(
          isA<ParseException>().having(
            (error) => error.message,
            'message',
            contains('.docx or PDF'),
          ),
        ),
      );
    });

    test('refuses an unsupported extension', () {
      expect(
        () => ParseService().parse(fileName: 'notes.txt', bytes: Uint8List(0)),
        throwsA(isA<ParseException>()),
      );
    });
  });

  group('PdfParser.joinVisualLines', () {
    // Regression for the OTES report (parser 1.4.1): Word's PDF export makes
    // `extractText` emit one word per line, which hid every prose section
    // from the splitter. The fix rebuilds lines from text-run coordinates;
    // these cases pin the regrouping rules without needing a real PDF.

    test('merges runs on the same visual row, ordered left to right', () {
      // Measured on the real report: the heading "3.2 Reliability" arrives as
      // two runs whose tops differ by one pixel (93 vs 92).
      final text = PdfParser.joinVisualLines([
        (top: 93, left: 40, text: '3.2'),
        (top: 92, left: 70, text: 'Reliability'),
      ]);
      expect(text, '3.2 Reliability');
    });

    test('keeps rows further apart than the tolerance on separate lines', () {
      final text = PdfParser.joinVisualLines([
        (top: 74, left: 40, text: '● 90% users feel comfortable'),
        (top: 110, left: 40, text: '3.3 Availability'),
      ]);
      expect(text, '● 90% users feel comfortable\n3.3 Availability');
    });

    test('orders rows top to bottom even when the input is unordered', () {
      final text = PdfParser.joinVisualLines([
        (top: 200, left: 40, text: 'second'),
        (top: 100, left: 40, text: 'first'),
      ]);
      expect(text, 'first\nsecond');
    });

    test('drops empty runs', () {
      final text = PdfParser.joinVisualLines([
        (top: 10, left: 40, text: ''),
        (top: 10, left: 80, text: 'kept'),
      ]);
      expect(text, 'kept');
    });

    test('drops repeated page-number footer noise', () {
      expect(
        PdfParser.stripPageNumberFooters(
          'Diagram title\nPage | 1 4 Page | 1 5 Page | 1 6',
        ),
        'Diagram title',
      );
    });

    test('keeps real requirements that mention a page', () {
      const text = 'The page must show the review result.';
      expect(PdfParser.stripPageNumberFooters(text), text);
    });

    test('keeps footer-only diagram pages as image candidates', () {
      final realText = List.filled(
        5,
        'A real text page with enough content to review.',
      ).join(' ');
      expect(
        PdfParser.detectImagePages(
          [realText, ''],
          rawPageTexts: [realText, 'Page | 1 4 Page | 1 5 Page | 1 6'],
        ),
        [1],
      );
    });
  });
}
