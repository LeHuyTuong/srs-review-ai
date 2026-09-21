import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart'
    show DiagramKind;
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/document_blueprint.dart';

void main() {
  const srsSection = SectionRange(
    id: 'C',
    title: 'Software Requirement Specification',
    printedStart: 22,
    printedEnd: 154,
    pdfStartIndex: 21,
    pdfEndIndex: 153,
  );
  const designSection = SectionRange(
    id: 'D',
    title: 'Software Design Description',
    printedStart: 155,
    printedEnd: 181,
    pdfStartIndex: 154,
    pdfEndIndex: 180,
  );
  const blueprint = DocumentBlueprint(
    sections: [srsSection, designSection],
    artifacts: [
      ArtifactRef(
        kind: ArtifactKind.table,
        number: 22,
        caption: 'USE CASE – Kick a student out of group',
        normalizedCaption: 'kick a student out of group',
        printedPage: 54,
        pdfPageIndex: 53,
        sectionId: 'C',
      ),
      ArtifactRef(
        kind: ArtifactKind.figure,
        number: 75,
        caption: 'Class Diagram',
        normalizedCaption: 'class diagram',
        printedPage: 160,
        pdfPageIndex: 159,
        sectionId: 'D',
        diagramKind: DiagramKind.classDiagram,
      ),
      ArtifactRef(
        kind: ArtifactKind.figure,
        number: 90,
        caption: 'ERD Diagram',
        normalizedCaption: 'erd diagram',
        printedPage: 180,
        sectionId: 'D',
        diagramKind: DiagramKind.erd,
      ),
    ],
    pageOffset: 0,
    tocPageIndexes: {0, 1, 2},
    trusted: true,
  );

  group('ArtifactRef', () {
    test('names itself the way the document does', () {
      expect(blueprint.artifacts.first.label, 'Table 22');
      expect(blueprint.artifacts[1].label, 'Figure 75');
    });

    test('isResolved distinguishes a verified page from a hint', () {
      expect(blueprint.artifacts.first.isResolved, isTrue);
      expect(blueprint.artifacts.last.isResolved, isFalse);
    });

    test('tables and figures split by kind', () {
      expect(blueprint.tables.map((a) => a.label), ['Table 22']);
      expect(blueprint.figures.map((a) => a.label), ['Figure 75', 'Figure 90']);
    });
  });

  group('SectionRange', () {
    test('contains only the pages inside its span', () {
      expect(srsSection.containsIndex(21), isTrue);
      expect(srsSection.containsIndex(153), isTrue);
      expect(srsSection.containsIndex(154), isFalse);
      expect(designSection.containsIndex(154), isTrue);
    });

    test('title matching uses the caller\'s regex, no case is assumed', () {
      expect(
        srsSection.matchesTitle(
          RegExp('requirement specification', caseSensitive: false),
        ),
        isTrue,
      );
      expect(srsSection.matchesTitle(RegExp('requirement specification')), isFalse);
      expect(srsSection.matchesTitle(RegExp('design')), isFalse);
    });
  });

  group('DocumentBlueprint', () {
    test('sectionOf finds the range a page belongs to', () {
      expect(blueprint.sectionOf(21)?.id, 'C');
      expect(blueprint.sectionOf(100)?.id, 'C');
      expect(blueprint.sectionOf(160)?.id, 'D');
    });

    test('sectionOf returns null outside every declared range', () {
      expect(blueprint.sectionOf(5), isNull);
      expect(blueprint.sectionOf(200), isNull);
    });

    test('srsSection picks the requirements chapter, not just any section', () {
      expect(blueprint.srsSection?.id, 'C');
    });

    test('srsSection accepts the short form some reports use', () {
      const short = DocumentBlueprint(
        sections: [
          SectionRange(
            id: 'B',
            title: 'SRS',
            printedStart: 10,
            printedEnd: 60,
            pdfStartIndex: 9,
            pdfEndIndex: 59,
          ),
        ],
        artifacts: [],
        pageOffset: 0,
        tocPageIndexes: {},
        trusted: false,
      );
      expect(short.srsSection?.id, 'B');
    });

    test('empty blueprint is empty and has no SRS section', () {
      expect(DocumentBlueprint.empty.isEmpty, isTrue);
      expect(DocumentBlueprint.empty.isNotEmpty, isFalse);
      expect(DocumentBlueprint.empty.srsSection, isNull);
    });
  });

  group('blueprint CheckIds', () {
    const blueprintChecks = [
      CheckId.duplicateCaption,
      CheckId.numberingGap,
      CheckId.missingSection,
      CheckId.unclassifiedFigure,
      CheckId.captionPageMismatch,
    ];

    test('every index check is flagged as a blueprint check', () {
      for (final check in blueprintChecks) {
        expect(check.isBlueprintCheck, isTrue, reason: check.name);
      }
    });

    test('other families are not blueprint checks', () {
      expect(CheckId.ucCount.isBlueprintCheck, isFalse);
      expect(CheckId.duplicateIds.isBlueprintCheck, isFalse);
      expect(CheckId.crossArtifactName.isBlueprintCheck, isFalse);
    });

    test('wires are unique and stable — the ledger key depends on them', () {
      final wires = CheckId.values.map((c) => c.wire).toList();
      expect(wires.toSet().length, wires.length);
      expect(CheckId.duplicateCaption.wire, 'duplicate_caption');
      expect(CheckId.numberingGap.wire, 'numbering_gap');
      expect(CheckId.missingSection.wire, 'missing_section');
      expect(CheckId.unclassifiedFigure.wire, 'unclassified_figure');
      expect(CheckId.captionPageMismatch.wire, 'caption_page_mismatch');
    });

    test('a new wire is recognised as a deterministic finding key', () {
      expect(isDeterministicFindingKey('numbering_gap:figure:39-41'), isTrue);
      expect(isDeterministicFindingKey('SEQ-CLS-01'), isFalse);
    });
  });
}
