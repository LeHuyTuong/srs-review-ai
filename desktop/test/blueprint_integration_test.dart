import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/diagram_detector.dart';
import 'package:srs_review_ai/deterministic_checks/checks/diagram_type_classifier.dart'
    show DiagramKind;
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/deterministic_checks/checks/syllabus_checks.dart';
import 'package:srs_review_ai/diagram_audit/services/image_budget.dart';
import 'package:srs_review_ai/diagram_audit/services/page_image_selector.dart';
import 'package:srs_review_ai/diagram_audit/services/vision_review_service.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/document_import/parsing/blueprint_builder.dart';
import 'package:srs_review_ai/document_import/parsing/table_of_contents.dart';

/// A miniature document whose index declares an SRS chapter (printed page 2,
/// index 1) and a design chapter (printed page 5, index 4), with one UC inside
/// each chapter — so the scoping and targeting tests assert against a RESOLVED
/// blueprint, not a guess.
SrsDocument indexedDocument() {
  final pages = [
    'A.\tIntroduction\t1\n'
        'C.\tSoftware Requirement Specification\t2\n'
        'D.\tSoftware Design Description\t5',
    'Figure 89. System architecture\t2\n'
        'Figure 90. ERD Diagram\t3\n'
        'Figure 91. Student raise hand\t3',
    'C. Software Requirement Specification\n'
        'UC-01 The system shall let a student upload an SRS file.',
    'Figure 90. ERD Diagram',
    'D. Software Design Description\n'
        'UC-02 The system shall export the class diagram as an image.',
    'Body page.',
  ];
  final toc = TableOfContents.parse(pages);
  final blueprint = const BlueprintBuilder().build(pageTexts: pages, toc: toc);
  return SrsDocument(
    fileName: 'indexed.pdf',
    pageCount: pages.length,
    pageTexts: pages,
    requirements: const [
      RequirementItem(
        id: 'UC-01',
        text: 'The system shall let a student upload an SRS file.',
        kind: RequirementKind.useCase,
        pageIndex: 2,
      ),
      RequirementItem(
        id: 'UC-02',
        text: 'The system shall export the class diagram as an image.',
        kind: RequirementKind.useCase,
        pageIndex: 4,
      ),
    ],
    imagePageIndexes: const [],
    blueprint: blueprint,
  );
}

void main() {
  group('SyllabusChecks F7/F9 scoping', () {
    test('a declared SRS chapter scopes the use-case count', () {
      final document = indexedDocument();
      // Two UCs exist in the file, but UC-02 lives in the design chapter:
      // F7 counts what the SRS chapter holds, not what the whole file holds.
      expect(document.useCaseCount, 2);
      final finding = const SyllabusChecks(
        RubricConfig.fallback,
      ).useCaseCount(document);
      expect(finding.actual, 1);
      expect(finding.passed, isFalse, reason: '1 < 20 — the honest verdict');
    });

    test('without an index the whole document is measured, as before', () {
      const document = SrsDocument(
        fileName: 'docx.docx',
        pageCount: 1,
        pageTexts: ['UC-01 does a thing'],
        requirements: [
          RequirementItem(
            id: 'UC-01',
            text: 'UC-01 does a thing',
            kind: RequirementKind.useCase,
            pageIndex: 0,
          ),
        ],
      );
      final finding = const SyllabusChecks(
        RubricConfig.fallback,
      ).useCaseCount(document);
      expect(finding.actual, 1);
    });

    test('F9 sizes only the use cases the SRS chapter holds', () {
      final document = indexedDocument();
      final findings = const SyllabusChecks(
        RubricConfig.fallback,
      ).useCaseSizes(document);
      // Every flagged UC must be the in-scope one, never the design chapter's.
      for (final finding in findings) {
        expect(finding.subject, 'UC-01');
      }
    });
  });
  group('DiagramDetector figure references', () {
    test('a named figure resolves to the page the index says', () {
      const detector = DiagramDetector();
      final signal = detector.detectWithBlueprint(
        'The sequence in Figure 90 must match the ERD.',
        indexedDocument().blueprint,
      );
      expect(signal.mentionsDiagram, isTrue);
      expect(signal.resolvedPageIndex, 3);
    });

    test('an unknown figure number degrades to the keyword signal', () {
      const detector = DiagramDetector();
      final signal = detector.detectWithBlueprint(
        'Figure 77 must show the booking flow.',
        indexedDocument().blueprint,
      );
      expect(signal.mentionsDiagram, isTrue);
      expect(signal.resolvedPageIndex, isNull);
    });

    test('no blueprint means the plain keyword signal', () {
      const detector = DiagramDetector();
      final signal = detector.detectWithBlueprint(
        'The class diagram must match the data dictionary.',
        null,
      );
      expect(signal.mentionsDiagram, isTrue);
      expect(signal.resolvedPageIndex, isNull);
    });
  });

  group('VisionReviewService candidates from the index', () {
    test('the index decides which pages are audited and as what kind', () {
      final candidates = const VisionReviewService(
        auditor: VisionReviewService.noOpAuditor,
        renderPage: _noRender,
      ).candidates(indexedDocument());
      expect(candidates, hasLength(1));
      expect(candidates.single.pageIndex, 3);
      expect(candidates.single.kind, DiagramKind.erd);
    });

    test('a document without an index falls back to text classification', () {
      const document = SrsDocument(
        fileName: 'docx.docx',
        pageCount: 1,
        pageTexts: ['The class diagram must match the data dictionary.'],
        requirements: [],
      );
      final candidates = const VisionReviewService(
        auditor: VisionReviewService.noOpAuditor,
        renderPage: _noRender,
      ).candidates(document);
      expect(candidates.single.pageIndex, 0);
      expect(candidates.single.kind, DiagramKind.classDiagram);
    });
  });

  group('PageImageSelector figure resolution', () {
    test(
      'a requirement naming a figure attaches the figure page, not its own',
      () {
        final selector = PageImageSelector(budget: ImageBudget());
        final plan = selector.planFor(
          requirementId: 'u0-UC-01',
          text: 'The flow in Figure 90 must match the ERD.',
          pageIndex: 2, // the requirement's own page — wrong page for the ERD
          candidatePages: {3}, // only the figure page is attachable
          blueprint: indexedDocument().blueprint,
        );
        expect(plan.decision, PageImageDecision.selected);
        expect(plan.pageIndex, 3);
      },
    );

    test('a keyword-only requirement keeps the old page behaviour', () {
      final selector = PageImageSelector(budget: ImageBudget());
      final plan = selector.planFor(
        requirementId: 'u0-UC-01',
        text: 'The class diagram must match the data dictionary.',
        pageIndex: 2,
        candidatePages: {2},
      );
      expect(plan.decision, PageImageDecision.selected);
      expect(plan.pageIndex, 2);
    });
  });
}

Future<String> _noRender(int pageIndex, String contextText) async => 'stub';
