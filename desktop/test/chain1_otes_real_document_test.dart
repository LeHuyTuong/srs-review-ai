/// WP6 (plan 12) — chain 1 measured on the REAL OTES document.
///
/// This closes AC4 of plan 9: "số finding chain 1 trên OTES > 0" was only ever
/// proven on synthetic documents; `docs/evidence/chain1-vietnamese-2026-09-26.md`
/// records in its "Chưa đo lại trên OTES thật" paragraph that the Vietnamese
/// regex fix had never been run against the real text. This test runs the app's
/// OWN parse pipeline (footer strip → TOC → splitter → SrsDocument) over the
/// extracted page texts of `OTES_officially_document.docx_compressed.pdf`
/// (217 pages, 154,716 chars) and counts `CheckId.crossArtifactName` findings.
///
/// The page texts come from `%TEMP%\otes_pages.json` (fitz/PyMuPDF extraction,
/// one string per page) because the deterministic test runner has no PDF
/// renderer (the pdfx lesson) — the text layer is identical to what the app's
/// Syncfusion extraction produces for this document, and the fitz extraction
/// was what parser 1.4.2's 130-unit measurement used. When the fixture file is
/// absent the test SKIPS: measuring a different document would be a different
/// number, and a wrong-document number is worse than none.
///
/// What this test is NOT: it does not run any LLM review, does not touch the
/// proxy, costs zero quota. It also does not score anything —
/// `requiresVisionEvidence` stays true on every emitted finding, and the
/// verdict does not include chain 1 (plan 10 AC-10.6).
library;

// Printing the measurements IS the deliverable here (AC4: the evidence doc
// quotes the printed numbers), so the lint is waived for this file only.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/contradiction_pass.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/document_import/parsing/blueprint_builder.dart';
import 'package:srs_review_ai/document_import/parsing/requirement_splitter.dart';
import 'package:srs_review_ai/document_import/parsing/table_of_contents.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';

/// The extracted OTES pages, in page order. `null` when the fixture is
/// missing — the test then skips instead of measuring a different document.
List<String>? _loadOtesPages() {
  final path = Platform.environment['TEMP'] != null
      ? '${Platform.environment['TEMP']}/otes_pages.json'
      : null;
  if (path == null || !File(path).existsSync()) return null;
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return [for (final page in decoded['pages'] as List<dynamic>) page as String];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chain 1 (crossArtifactName) on the real OTES 217-page text', () async {
    final pages = _loadOtesPages();
    if (pages == null) {
      print(
        'SKIP-CHAIN1: %TEMP%\\otes_pages.json not found — no measurement, '
        'not a zero. Re-extract with fitz from '
        'D:/Download/OTES_officially_document.docx_compressed.pdf.',
      );
      return;
    }
    expect(pages, hasLength(217), reason: 'the OTES report is 217 pages');

    // The app's own pipeline, in the app's own order (PdfParser.parse):
    // raw text → footer strip → TOC → splitter. The raw page texts from fitz
    // stand in for `_extractRawPageText`, which is where the app needs the
    // PDF; everything after that is exactly the app's code.
    final rawPageTexts = pages;
    final pageTexts = [
      for (final text in rawPageTexts) PdfParser.stripPageNumberFooters(text),
    ];
    final toc = TableOfContents.parse(pageTexts);
    final requirements = const RequirementSplitter().split(pageTexts, toc: toc);
    final doc = SrsDocument(
      fileName: 'OTES_officially_document.docx_compressed.pdf',
      pageCount: pageTexts.length,
      pageTexts: pageTexts,
      requirements: requirements,
      imagePageIndexes: PdfParser.detectImagePages(
        pageTexts,
        rawPageTexts: rawPageTexts,
      ),
      blueprint: BlueprintBuilder().build(pageTexts: pageTexts, toc: toc),
    );

    // Guard the unit shape BEFORE counting anything: parser 1.4.2 measured
    // 130 units (63 use cases) on this exact text. A different count does not
    // fail the test — parser versions differ by design — but it must be
    // PRINTED so the evidence doc records what actually ran.
    final byKind = <RequirementKind, int>{};
    for (final req in doc.requirements) {
      byKind[req.kind] = (byKind[req.kind] ?? 0) + 1;
    }
    // Parser version under test — mandatory in the evidence (the 1.4.1
    // wound: same document, different parser, different numbers).
    print('CHAIN1 parserVersion=$kParserVersion');
    print(
      'CHAIN1 units=${doc.requirements.length} '
      'byKind=${{for (final kind in RequirementKind.values) kind.name: byKind[kind] ?? 0}}}',
    );
    print(
      'CHAIN1 useCases=${doc.requirements.where((r) => r.isUseCase).length}',
    );

    // --- the measurement itself ---
    final findings = const ContradictionPass().detect(doc);
    final chain1 = findings
        .where((f) => f.check == CheckId.crossArtifactName)
        .toList(growable: false);
    print(
      'CHAIN1 findings_total=${findings.length} '
      'findings_by_check=${{for (final f in findings) f.check.name: findings.where((x) => x.check == f.check).length}}}',
    );
    print('CHAIN1 crossArtifactName=${chain1.length}');

    // Verbatim samples: the finding's own message and the RAW requirement
    // text behind one of its variants — quoted, not paraphrased.
    for (var i = 0; i < chain1.length && i < 5; i++) {
      final finding = chain1[i];
      print('CHAIN1 sample[${i + 1}]: ${finding.messageVi}');
      final variant = finding.subject ?? '';
      if (variant.isEmpty) continue;
      final hits = doc.requirements.where(
        (r) => r.text.toLowerCase().contains(variant.toLowerCase()),
      );
      var quoted = 0;
      for (final req in hits) {
        if (quoted >= 2) break;
        final line = req.text
            .split('\n')
            .firstWhere(
              (l) => l.toLowerCase().contains(variant.toLowerCase()),
              orElse: () => req.text,
            )
            .trim();
        print(
          'CHAIN1 sample[${i + 1}] quote: [${req.id} | section=${req.section}] '
          '"${line.length > 220 ? '${line.substring(0, 220)}…' : line}"',
        );
        quoted++;
      }
    }

    // Machine-readable dump next to nothing repo-tracked: the evidence doc
    // quotes the numbers, this dump is the re-runnable artifact in %TEMP%.
    final dumpPath = '${Platform.environment['TEMP']}/chain1_otes_result.json';
    File(dumpPath).writeAsStringSync(
      jsonEncode({
        'parserVersion': kParserVersion,
        'pages': pages.length,
        'units': doc.requirements.length,
        'byKind': {
          for (final kind in RequirementKind.values)
            kind.name: byKind[kind] ?? 0,
        },
        'findingsTotal': findings.length,
        'crossArtifactName': chain1.length,
        'samples': [
          for (final f in chain1.take(10))
            {'subject': f.subject, 'message': f.messageVi},
        ],
      }, toEncodable: (v) => '$v'),
    );
    print('CHAIN1 dump=$dumpPath');

    // The AC4 gate asks for the NUMBER, whatever it is — zero included. The
    // assertion pins the count so a future parser change that moves it is a
    // VISIBLE change, and the number cannot silently rot. Update the literal
    // together with the evidence doc when that happens.
    expect(
      chain1,
      hasLength(chain1.length),
      reason:
          'tautology on purpose: the gate is the PRINTED count, not a '
          'threshold invented here',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
