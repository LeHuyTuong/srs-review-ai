/// M0 harness — real Syncfusion end-to-end over the OTES SRS, not a pdftotext
/// stand-in. Emits the inventory manifest the roadmap's M0 gate asks for and
/// reconciles it against the 63/52/51 source baseline.
///
/// Run (the PDF stays local; nothing here is committed as a fixture):
///   flutter test tool/otes_m0_manifest.dart
///
/// It is a `flutter test` file rather than a `dart run` script on purpose:
/// syncfusion_flutter_pdf is a Flutter package, so it needs the test VM's
/// bindings — but it is pure Dart underneath, so it does NOT need a macOS
/// desktop build. That distinction is what unblocks M0 on this machine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/document_import/parsing/requirement_splitter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// 1-based, inclusive — the SRS body of OTES. Page 17 (scope) and everything
/// before 23 is context, deliberately outside the use-case inventory.
const int _srsFirstPage = 23;
const int _srsLastPage = 155;

/// Overridable so the harness is not welded to one machine:
///   OTES_PDF=/path/to.pdf flutter test tool/otes_m0_manifest.dart
final String _sourcePath =
    Platform.environment['OTES_PDF'] ??
    '${Platform.environment['HOME']}/Downloads/OTES_officially_document.docx.pdf';
const String _outPath = '/tmp/otes-m0-manifest.json';

/// In reading-order extraction the Word table cell holding the id lands alone
/// on its own line, so the id anchors the line rather than trailing a label.
final RegExp _idOnOwnLine = RegExp(r'^\s*(UC\d{1,3})\s*$');

/// Ids with four or more digits — `UC0114`, `UC0134` in OTES. They are a
/// defect in the source document, but the shipping splitter's `\d{1,3}\b`
/// cannot match them and drops the whole use case *silently*, which is the
/// app's defect. Counted here so M1 has a number to fix against.
final RegExp _malformedIdOnOwnLine = RegExp(r'^\s*(UC\d{4,})\s*$');

/// The label cell that opens every use-case table. Counted separately: it is
/// the most reliable "a use case starts here" marker that does not depend on
/// the id cell surviving extraction.
final RegExp _useCaseNoLabel = RegExp(
  r'^\s*use\s*case\s*no\.?\s*$',
  caseSensitive: false,
);

void main() {
  test('M0: Syncfusion E2E inventory of the OTES SRS', () {
    final file = File(_sourcePath);
    if (!file.existsSync()) {
      markTestSkipped('OTES PDF not present at $_sourcePath — M0 needs it.');
      return;
    }

    final bytes = file.readAsBytesSync();
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);

    final allPages = <String>[];
    for (var i = 0; i < document.pages.count; i++) {
      allPages.add(extractor.extractText(startPageIndex: i, endPageIndex: i));
    }
    document.dispose();

    final srsPages = allPages.sublist(_srsFirstPage - 1, _srsLastPage);

    // ---- source truth, measured on the SAME text the app will parse ----
    final headerPages = <int>[];
    final idOccurrences = <_IdOccurrence>[];
    final malformed = <_IdOccurrence>[];
    for (var p = 0; p < srsPages.length; p++) {
      final physicalPage = _srsFirstPage + p;
      for (final raw in srsPages[p].split('\n')) {
        if (_useCaseNoLabel.hasMatch(raw)) headerPages.add(physicalPage);
        final m = _idOnOwnLine.firstMatch(raw);
        if (m != null) {
          idOccurrences.add(_IdOccurrence(m.group(1)!, physicalPage));
        }
        final bad = _malformedIdOnOwnLine.firstMatch(raw);
        if (bad != null) {
          malformed.add(_IdOccurrence(bad.group(1)!, physicalPage));
        }
      }
    }

    // Keep one raw page next to the manifest: the whole point of M0 is that
    // nobody has to trust a claim about what the extractor emits.
    final sample = StringBuffer();
    for (final page in [18, 24, 30, 56]) {
      sample
        ..writeln('===== physical page $page =====')
        ..writeln(allPages[page - 1].split('\n').take(18).join('\n'));
    }
    File('/tmp/otes-m0-sample-pages.txt').writeAsStringSync(sample.toString());

    final literalIds = idOccurrences.map((o) => o.id).toList();
    final numericIds = literalIds.map((s) => int.parse(s.substring(2))).toSet();

    // ---- what the shipping pipeline actually produces ----
    const splitter = RequirementSplitter();
    final items = splitter.split(srsPages);
    final useCases = items.where((i) => i.isUseCase).toList();

    final manifest = {
      'kind': 'm0_syncfusion_end_to_end',
      'source_fnv1a64': _fnv1a64(bytes),
      'source_bytes': bytes.length,
      'pdf_total_pages': allPages.length,
      'scope_pdf_pages': [_srsFirstPage, _srsLastPage],
      'extraction':
          'syncfusion_flutter_pdf PdfTextExtractor per page '
          '-> RequirementSplitter (the real ParseService path)',
      'source_use_case_no_labels': headerPages.length,
      'malformed_ids_dropped_silently': [
        for (final o in malformed) {'id': o.id, 'physical_page': o.page},
      ],
      'source_id_occurrences': idOccurrences.length,
      'source_literal_unique_ids': literalIds.toSet().length,
      'source_numeric_unique_ids': numericIds.length,
      'splitter_total_items': items.length,
      'splitter_use_case_items': useCases.length,
      'use_cases': [
        for (final uc in useCases)
          {
            'id': uc.id,
            // pageIndex is relative to the slice handed to the splitter;
            // report the physical 1-based page a marker can actually jump to.
            // It is nullable — null means the splitter never anchored this
            // item to a page, which is itself an M1 defect worth seeing.
            'physical_page': uc.pageIndex == null
                ? null
                : _srsFirstPage + uc.pageIndex!,
            'section': uc.section,
            'chars': uc.text.length,
          },
      ],
      'id_occurrences': [
        for (final o in idOccurrences) {'id': o.id, 'physical_page': o.page},
      ],
    };

    final json = const JsonEncoder.withIndent('  ').convert(manifest);
    File(_outPath).writeAsStringSync('$json\n');

    // Printed so the run itself is the evidence, not a claim about it.
    stdout.writeln('--- M0 reconciliation ---');
    stdout.writeln('pdf pages                : ${allPages.length}');
    stdout.writeln('"Use Case No." labels    : ${headerPages.length}');
    stdout.writeln('id occurrences on own ln : ${idOccurrences.length}');
    stdout.writeln('unique literal ids       : ${literalIds.toSet().length}');
    stdout.writeln('unique numeric ids       : ${numericIds.length}');
    stdout.writeln('splitter items           : ${items.length}');
    stdout.writeln('splitter use cases       : ${useCases.length}');
    final thin = useCases.where((u) => u.text.length < 400).length;
    stdout.writeln('use cases < 400 chars    : $thin / ${useCases.length}');
    stdout.writeln(
      'malformed ids dropped    : ${malformed.length} '
      '${malformed.map((o) => '${o.id}@p${o.page}').toList()}',
    );
    stdout.writeln('manifest -> $_outPath');
  });
}

/// FNV-1a, 64-bit, as hex. Enough to prove "the same file was measured" in a
/// manifest, and it avoids taking a direct dependency on `crypto` — which is
/// only a transitive dep here, so importing it would trip
/// `depend_on_referenced_packages` under `--fatal-infos`.
/// Plain `int` arithmetic, not BigInt: on the Dart VM `int` is 64-bit and
/// multiplication wraps, which is exactly FNV's modulo-2^64 step — and BigInt
/// over 27 MB of bytes would take minutes.
String _fnv1a64(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash = (hash ^ b) * 0x100000001b3;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

class _IdOccurrence {
  const _IdOccurrence(this.id, this.page);
  final String id;
  final int page;
}
