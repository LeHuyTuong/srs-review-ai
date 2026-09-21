import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart'
    show DiagramKind;
import 'package:srs_review_ai/data/models/document_blueprint.dart';
import 'package:srs_review_ai/data/parsing/blueprint_builder.dart';
import 'package:srs_review_ai/data/parsing/table_of_contents.dart';

/// A miniature capstone report: index on the front pages, body behind it, and
/// printed page numbers that line up with `pageTexts` (index 0 = printed 1).
///
/// ```
/// index 0 (printed 1)  chapter list A–E
/// index 1 (printed 2)  List of Tables + List of Figures
/// index 2 (printed 3)  body: B heading
/// index 3 (printed 4)  body: C heading + UC-01
/// index 4 (printed 5)  caption Table 9
/// index 5 (printed 6)  body: D heading + caption Table 22 + Figure 75
/// index 6 (printed 7)  body: E heading + caption Table 23 + Figure 90
/// index 7 (printed 8)  appendix
/// ```
List<String> capstonePages() => [
  'A.\tIntroduction\t2\n'
      'B.\tSoftware Project Management Plan\t3\n'
      'C.\tSoftware Requirement Specification\t4\n'
      'D.\tSoftware Design Description\t6\n'
      'E.\tSystem Implementation & Test\t7',
  'Table 9. Unauthorized Login\t5\n'
      'Table 22. Use Case - Kick a student out of group\t6\n'
      'Table 23. Use Case - Kick a student out of group\t7\n'
      'Figure 75. Class Diagram\t6\n'
      'Figure 90. ERD Diagram\t7',
  'B. Software Project Management Plan\nMilestones and deliverables.',
  'C. Software Requirement Specification\n'
      'UC-01 The system shall let a student upload an SRS file.',
  'Table 9. Unauthorized Login',
  'D. Software Design Description\n'
      'Table 22. Use Case - Kick a student out of group\n'
      'Figure 75. Class Diagram',
  'E. System Implementation & Test\n'
      'Table 23. Use Case - Kick a student out of group\n'
      'Figure 90. ERD Diagram',
  'Appendix A. Interview notes',
];

void main() {
  const builder = BlueprintBuilder();

  DocumentBlueprint build(List<String> pages) =>
      builder.build(pageTexts: pages, toc: TableOfContents.parse(pages))!;

  group('index absent', () {
    test('a document with no index yields no blueprint', () {
      final pages = [
        'FR-01 The system shall allow a student to upload an SRS file.\n'
            'UC-01 Search for a book',
      ];
      expect(
        builder.build(pageTexts: pages, toc: TableOfContents.parse(pages)),
        isNull,
      );
    });

    test('no pages, no blueprint', () {
      expect(
        builder.build(pageTexts: const [], toc: TableOfContents.empty),
        isNull,
      );
    });
  });

  group('standalone SRS index', () {
    test('roman-numbered front matter counts as chapter entries', () {
      // The official SRS template: `I.`/`II.` for the front matter, then
      // `1.` … `5.` for the body. The roman lines are entries too, so the
      // front matter gets section ranges and the index page still qualifies
      // when the body outline alone is shorter than `minEntriesPerTocPage`.
      final pages = [
        'I.\tRecord of Changes\t2\n'
            'II.\tTable of Contents\t3\n'
            '1.\tProduct Overview\t4\n'
            '2.\tUser Requirements\t5\n'
            '3.\tFunctional Requirements\t6',
        'Record of Changes',
        'Table of Contents',
        '1. Product Overview\nThe system helps lecturers.',
        '2. User Requirements\nUC-01 Login',
        '3. Functional Requirements\nScreens.',
      ];
      final toc = TableOfContents.parse(pages);

      expect(toc.pageIndexes, {0});
      expect(toc.chapters.map((c) => c.title), [
        'Record of Changes',
        'Table of Contents',
        'Product Overview',
        'User Requirements',
        'Functional Requirements',
      ]);
    });
  });

  group('aligned index (offset 0)', () {
    late DocumentBlueprint blueprint;
    setUpAll(() => blueprint = build(capstonePages()));

    test('page mapping is verified against the body', () {
      expect(blueprint.pageOffset, 0);
      expect(blueprint.trusted, isTrue);
    });

    test('chapter list becomes ranges with both ends', () {
      expect(blueprint.sections.map((s) => s.id), ['A', 'B', 'C', 'D', 'E']);
      final c = blueprint.sectionOf(3)!;
      expect(c.title, 'Software Requirement Specification');
      expect(c.printedStart, 4);
      expect(c.printedEnd, 5);
      expect(c.pdfStartIndex, 3);
      expect(c.pdfEndIndex, 4);
    });

    test('the index pages are recorded so nothing re-reads them as content', () {
      expect(blueprint.tocPageIndexes, {0, 1});
    });

    test('every artifact lands on the page that really carries its caption', () {
      final byLabel = {
        for (final a in blueprint.artifacts) a.label: a,
      };
      expect(byLabel['Table 9']!.pdfPageIndex, 4);
      expect(byLabel['Table 22']!.pdfPageIndex, 5);
      expect(byLabel['Table 23']!.pdfPageIndex, 6);
      expect(byLabel['Figure 75']!.pdfPageIndex, 5);
      expect(byLabel['Figure 90']!.pdfPageIndex, 6);
    });

    test('figures carry the UML kind their caption names', () {
      final figures = {
        for (final f in blueprint.figures) f.label: f.diagramKind,
      };
      expect(figures['Figure 75'], DiagramKind.classDiagram);
      expect(figures['Figure 90'], DiagramKind.erd);
    });

    test('artifacts are placed in the section that holds their page', () {
      final byLabel = {
        for (final a in blueprint.artifacts) a.label: a.sectionId,
      };
      expect(byLabel['Table 22'], 'D');
      expect(byLabel['Figure 90'], 'E');
    });

    test('the SRS chapter is found for scoping', () {
      expect(blueprint.srsSection?.id, 'C');
    });
  });

  group('front matter pushes printed page 1 off index 0', () {
    test('the offset is recovered from the chapter titles', () {
      final pages = [
        'Capstone Project Report\nOnline Bookstore',
        'Revision history\nVersion 1.0',
        ...capstonePages(),
      ];
      final blueprint = build(pages);

      expect(blueprint.pageOffset, 2);
      expect(blueprint.trusted, isTrue);
      expect(blueprint.sectionOf(5)?.id, 'C');
      final table9 = blueprint.artifacts.firstWhere(
        (a) => a.label == 'Table 9',
      );
      expect(table9.pdfPageIndex, 6);
      final figure90 = blueprint.artifacts.firstWhere(
        (a) => a.label == 'Figure 90',
      );
      expect(figure90.pdfPageIndex, 8);
    });
  });

  group('degraded indexes', () {
    test('an index whose pages cannot be verified is untrusted, not dropped', () {
      final pages = [
        'A.\tIntroduction\t2\n'
            'B.\tSoftware Project Management Plan\t3\n'
            'C.\tSoftware Requirement Specification\t4\n'
            'D.\tSoftware Design Description\t6\n'
            'E.\tSystem Implementation & Test\t7',
        'Table 9. Unauthorized Login\t5\n'
            'Table 22. Use Case - Kick a student out of group\t6\n'
            'Table 23. Use Case - Kick a student out of group\t7\n'
            'Figure 75. Class Diagram\t6\n'
            'Figure 90. ERD Diagram\t7',
        'Body text without a single chapter heading.',
      ];
      final blueprint = build(pages);

      expect(blueprint.trusted, isFalse);
      expect(blueprint.pageOffset, 0);
      expect(blueprint.sections, hasLength(5));
      expect(blueprint.artifacts.every((a) => !a.isResolved), isTrue);
    });

    test('a caption that is not where the index says stays unresolved', () {
      final pages = capstonePages();
      pages[4] = 'A paragraph with nothing to index on it.';
      final blueprint = build(pages);

      expect(blueprint.trusted, isTrue);
      final table9 = blueprint.artifacts.firstWhere(
        (a) => a.label == 'Table 9',
      );
      expect(table9.pdfPageIndex, isNull);
      expect(table9.printedPage, 5);
      final table22 = blueprint.artifacts.firstWhere(
        (a) => a.label == 'Table 22',
      );
      expect(
        table22.pdfPageIndex,
        5,
        reason: 'unaffected neighbours still resolve',
      );
    });

    test('two artifacts sharing one caption still resolve to their own pages',
        () {
      // The real defect shape: three use cases called "Save student's video".
      // Caption text cannot tell them apart; the printed label can.
      final pages = [
        'A.\tIntroduction\t1\n'
            'C.\tSoftware Requirement Specification\t3\n'
            'D.\tSoftware Design Description\t5',
        'Table 40. Save student video\t5\n'
            'Table 42. Save student video\t6\n'
            'Table 43. Save student video\t7',
        'A page of prose.',
        'C. Software Requirement Specification',
        'Body prose again.',
        'Table 40. Save student video',
        'Table 42. Save student video',
        'Table 43. Save student video',
      ];
      final blueprint = build(pages);

      final byLabel = {
        for (final a in blueprint.artifacts) a.label: a.pdfPageIndex,
      };
      expect(byLabel['Table 40'], 5);
      expect(byLabel['Table 42'], 6);
      expect(byLabel['Table 43'], 7);
    });

    test('an artifact is never resolved to a page of the index itself', () {
      // The caption exists ONLY on the index page here. Reading it as the
      // artifact's page is the trap: the window search used to walk onto the
      // LoT/LoF page and hand the vision pass a page whose content is a pointer.
      // No body page repeats a chapter title either, so the mapping cannot be
      // verified — a page number here would be invention.
      final pages = [
        'A.\tIntroduction\t1\n'
            'C.\tSoftware Requirement Specification\t2\n'
            'D.\tSoftware Design Description\t3',
        'Table 9. Unauthorized Login\t2\n'
            'Table 10. Export students\t3\n'
            'Figure 75. Class Diagram\t3',
        'A page of prose that repeats nothing.',
        'Another page of prose.',
      ];
      final blueprint = build(pages);

      expect(blueprint.trusted, isFalse);
      expect(
        blueprint.artifacts.every((a) => !a.isResolved),
        isTrue,
        reason: 'the index is a pointer list, never the artifact itself',
      );
    });

    test('a caption naming no diagram kind is unknown, not null', () {
      final pages = [
        'A.\tIntroduction\t1\n'
            'C.\tSoftware Requirement Specification\t3\n'
            'D.\tSoftware Design Description\t3',
        'Figure 4. <Student> Raise hand\t3\n'
            'Figure 5. Class Diagram\t3\n'
            'Figure 6. Data flow of the checkout\t3',
        'Body page one.',
      ];
      final blueprint = build(pages);

      final kinds = {
        for (final f in blueprint.figures) f.label: f.diagramKind,
      };
      expect(kinds['Figure 4'], DiagramKind.unknown);
      expect(kinds['Figure 5'], DiagramKind.classDiagram);
      expect(kinds['Figure 6'], DiagramKind.unknown);
    });
  });

  group('caption folding', () {
    test('actor tags, dashes and casing all fold to one key', () {
      expect(
        normalizeCaption('USE CASE – Kick a student out of group'),
        'kick a student out of group',
      );
      expect(
        normalizeCaption('Use Case - Kick a Student Out Of Group'),
        'kick a student out of group',
      );
      expect(normalizeCaption('<Admin> Import students'), 'import students');
    });

    test('caption kind rules read the words, in priority order', () {
      expect(diagramKindForCaption('class diagram'), DiagramKind.classDiagram);
      expect(diagramKindForCaption('use case diagram'), DiagramKind.useCase);
      expect(diagramKindForCaption('sequence diagram'), DiagramKind.sequence);
      expect(diagramKindForCaption('activity diagram'), DiagramKind.activity);
      expect(diagramKindForCaption('state machine'), DiagramKind.stateMachine);
      expect(diagramKindForCaption('erd diagram'), DiagramKind.erd);
      expect(
        diagramKindForCaption('system architecture'),
        DiagramKind.component,
      );
      expect(diagramKindForCaption('raise hand'), DiagramKind.unknown);
    });
  });
}
