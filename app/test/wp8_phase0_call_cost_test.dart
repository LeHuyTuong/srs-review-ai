// ignore_for_file: avoid_print

/// WP8 gate 1, PHASE 0 — count the calls before spending anything.
///
/// The number of provider calls depends on how many units the app will attach a
/// page image to, and that is decided by the app's own selector
/// (`PageImageSelector.planFor`), not by a guess. So this prints the plan the
/// app would execute: units with an image reserved, units that stay text-only,
/// and the call count the batching rule implies.
///
/// It spends nothing: no key, no network, no provider. The diagram/vision path
/// is NOT counted here and the report says so — the vision audit needs RENDERED
/// pages, which need the PDF bytes, and this harness deliberately holds text
/// only. Counting it from text would be inventing a number.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/app_config.dart';
import 'package:srs_review_ai/diagram_audit/services/image_budget.dart';
import 'package:srs_review_ai/diagram_audit/services/page_image_selector.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/document_import/parsing/blueprint_builder.dart';
import 'package:srs_review_ai/document_import/parsing/requirement_splitter.dart';
import 'package:srs_review_ai/document_import/parsing/table_of_contents.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';

void main() {
  test('phase 0: the planned call count for one OTES run', () {
    final file = File(
      '${Platform.environment['TEMP']}/otes_pages.json',
    );
    if (!file.existsSync()) {
      print(
        'SKIP-PHASE0: %TEMP%\\otes_pages.json not found — no plan, no cost. '
        'Re-extract with fitz from '
        'D:/Download/OTES_officially_document.docx_compressed.pdf.',
      );
      return;
    }
    final pages = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, dynamic>()['pages'] as List<dynamic>;
    expect(pages, hasLength(217), reason: 'the OTES report is 217 pages');

    // The app's own pipeline, the same order `PdfParser.parse` uses.
    final rawPageTexts = pages.cast<String>();
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

    // The selector the repository uses, with the same budget object.
    final budget = ImageBudget();
    final selector = PageImageSelector(budget: budget);
    final candidates = doc.imagePageIndexes.toSet();

    final selectedPages = <int>{};
    var withImage = 0;
    final byDecision = <PageImageDecision, int>{};
    for (final req in doc.requirements) {
      final page = req.pageIndex;
      final plan = selector.planFor(
        requirementId: req.id,
        text: req.text,
        pageIndex: page,
        candidatePages: candidates,
        blueprint: doc.blueprint,
        pageText: (page != null && page < pageTexts.length)
            ? pageTexts[page]
            : null,
      );
      byDecision[plan.decision] = (byDecision[plan.decision] ?? 0) + 1;
      if (plan.decision == PageImageDecision.selected) {
        withImage++;
        final at = plan.pageIndex;
        if (at != null) selectedPages.add(at);
      }
    }

    final total = doc.requirements.length;
    final textOnly = total - withImage;
    const batch = AppConfig.reviewBatchSize;
    final batchedCalls = (textOnly + batch - 1) ~/ batch;
    final totalCalls = batchedCalls + withImage;

    print('PHASE0 batchSize=$batch');
    print('PHASE0 imageBudget=${budget.maxPages}');
    print('PHASE0 units=$total candidateImagePages=${candidates.length}');
    print('PHASE0 unitsWithImage=$withImage unitsTextOnly=$textOnly');
    print('PHASE0 distinctPagesShipped=${selectedPages.length}');
    print('PHASE0 decisions=$byDecision');
    print(
      'PHASE0 formula=calls=ceil($textOnly/$batch)+$withImage'
      ' => $batchedCalls+$withImage=$totalCalls',
    );
    print('PHASE0 visionPathCalls=NOT_COUNTED (needs rendered pages, not text)');

    // The reviewed list, exported for the paid run. Kept in the same harness on
    // purpose: the units a run reviews must be the ones THIS pipeline produced,
    // not a re-parse that might differ. Written outside the repo — it is OTES
    // text, not repo content.
    final outFile = File('${Platform.environment['TEMP']}/otes_units.json');
    outFile.writeAsStringSync(
      jsonEncode({
        'source': doc.fileName,
        'parserVersion': kParserVersion,
        'units': [
          for (final req in doc.requirements)
            {
              'requirement_id': req.id,
              'kind': req.kind.name,
              'text': req.text,
              'section': req.section,
              'page_index': req.pageIndex,
            },
        ],
      }),
    );
    print('PHASE0 unitsExported=${outFile.path}');
  });
}
