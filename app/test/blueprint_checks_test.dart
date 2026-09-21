import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/blueprint_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/document_blueprint.dart';
import 'package:srs_review_ai/data/models/review_models.dart' show Severity;
import 'package:srs_review_ai/data/parsing/blueprint_builder.dart';

/// The five report parts this check family expects, all present.
const List<SectionRange> _fullOutline = [
  SectionRange(
    id: 'A',
    title: 'Introduction',
    printedStart: 1,
    printedEnd: 9,
    pdfStartIndex: 0,
    pdfEndIndex: 8,
  ),
  SectionRange(
    id: 'B',
    title: 'Software Project Management Plan',
    printedStart: 10,
    printedEnd: 21,
    pdfStartIndex: 9,
    pdfEndIndex: 20,
  ),
  SectionRange(
    id: 'C',
    title: 'Software Requirement Specification',
    printedStart: 22,
    printedEnd: 154,
    pdfStartIndex: 21,
    pdfEndIndex: 153,
  ),
  SectionRange(
    id: 'D',
    title: 'Software Design Description',
    printedStart: 155,
    printedEnd: 181,
    pdfStartIndex: 154,
    pdfEndIndex: 180,
  ),
  SectionRange(
    id: 'E',
    title: 'System Implementation & Test',
    printedStart: 182,
    printedEnd: 194,
    pdfStartIndex: 181,
    pdfEndIndex: 193,
  ),
];

ArtifactRef _table({
  required int number,
  required String caption,
  required int printedPage,
  int? pdfPageIndex,
  String? sectionId,
}) => ArtifactRef(
  kind: ArtifactKind.table,
  number: number,
  caption: caption,
  normalizedCaption: normalizeCaption(caption),
  printedPage: printedPage,
  pdfPageIndex: pdfPageIndex,
  sectionId: sectionId,
);

ArtifactRef _figure({
  required int number,
  required String caption,
  required int printedPage,
  int? pdfPageIndex,
  String? sectionId,
}) => ArtifactRef(
  kind: ArtifactKind.figure,
  number: number,
  caption: caption,
  normalizedCaption: normalizeCaption(caption),
  printedPage: printedPage,
  pdfPageIndex: pdfPageIndex,
  sectionId: sectionId,
  diagramKind: diagramKindForCaption(normalizeCaption(caption)),
);

DocumentBlueprint _blueprint({
  List<SectionRange> sections = _fullOutline,
  List<ArtifactRef> artifacts = const [],
  bool trusted = true,
}) => DocumentBlueprint(
  sections: sections,
  artifacts: artifacts,
  pageOffset: 0,
  tocPageIndexes: const {0, 1},
  trusted: trusted,
);

void main() {
  const checks = BlueprintChecks();

  group('nothing to check', () {
    test('a document with no index produces no findings', () {
      expect(checks.runAll(null), isEmpty);
      expect(checks.runAll(DocumentBlueprint.empty), isEmpty);
    });

    test('a healthy index produces no findings', () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 22,
            caption: 'USE CASE – Create group',
            printedPage: 52,
            pdfPageIndex: 51,
            sectionId: 'C',
          ),
          _figure(
            number: 75,
            caption: 'Class Diagram',
            printedPage: 160,
            pdfPageIndex: 159,
            sectionId: 'D',
          ),
        ],
      );
      expect(checks.runAll(blueprint), isEmpty);
    });
  });

  group('duplicate captions', () {
    test('two tables with the same name are reported once, with both numbers',
        () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 22,
            caption: 'USE CASE – Kick a student out of group',
            printedPage: 54,
            pdfPageIndex: 53,
            sectionId: 'C',
          ),
          _table(
            number: 23,
            caption: 'Use Case - Kick a Student Out Of Group',
            printedPage: 56,
            pdfPageIndex: 55,
            sectionId: 'C',
          ),
        ],
      );
      final findings = checks.runAll(blueprint);

      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.check, CheckId.duplicateCaption);
      expect(finding.severity, Severity.medium);
      expect(finding.passed, isFalse);
      expect(finding.actual, 2);
      expect(finding.message, contains('Table 22'));
      expect(finding.message, contains('Table 23'));
      expect(finding.subject, 'kick a student out of group');
    });

    test('three tables sharing a caption collapse into one finding', () {
      final blueprint = _blueprint(
        artifacts: [
          for (final entry in const [
            (40, 91),
            (42, 95),
            (43, 96),
          ])
            _table(
              number: entry.$1,
              caption: "USE CASE - Save student's video",
              printedPage: entry.$2,
              pdfPageIndex: entry.$2 - 1,
              sectionId: 'C',
            ),
        ],
      );
      final findings = checks.duplicateCaptions(blueprint);

      expect(findings, hasLength(1));
      expect(findings.single.actual, 3);
      expect(findings.single.message, contains('Table 43'));
    });

    test('distinct captions are not duplicates', () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 1,
            caption: 'Create group',
            printedPage: 10,
            pdfPageIndex: 9,
            sectionId: 'B',
          ),
          _table(
            number: 2,
            caption: 'Delete semester',
            printedPage: 11,
            pdfPageIndex: 10,
            sectionId: 'B',
          ),
        ],
      );
      expect(checks.duplicateCaptions(blueprint), isEmpty);
    });
  });

  group('numbering gaps', () {
    test('a figure number missing inside one section is reported', () {
      final blueprint = _blueprint(
        artifacts: [
          _figure(
            number: 39,
            caption: 'Join teaching classroom',
            printedPage: 97,
            pdfPageIndex: 96,
            sectionId: 'D',
          ),
          _figure(
            number: 41,
            caption: 'Get students',
            printedPage: 100,
            pdfPageIndex: 99,
            sectionId: 'D',
          ),
        ],
      );
      final findings = checks.numberingGaps(blueprint);

      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.numberingGap);
      expect(findings.single.severity, Severity.low);
      expect(findings.single.message, contains('Figure 40'));
    });

    test('the same jump across two sections is not a gap', () {
      final blueprint = _blueprint(
        artifacts: [
          _figure(
            number: 42,
            caption: 'Get students',
            printedPage: 100,
            pdfPageIndex: 99,
            sectionId: 'C',
          ),
          _figure(
            number: 75,
            caption: 'Class Diagram',
            printedPage: 160,
            pdfPageIndex: 159,
            sectionId: 'D',
          ),
        ],
      );
      expect(checks.numberingGaps(blueprint), isEmpty);
    });

    test('a wide jump inside one section is treated as a new run', () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 23,
            caption: 'Export Lecturer',
            printedPage: 56,
            pdfPageIndex: 55,
            sectionId: 'C',
          ),
          _table(
            number: 40,
            caption: 'Save video',
            printedPage: 91,
            pdfPageIndex: 90,
            sectionId: 'C',
          ),
        ],
      );
      expect(
        checks.numberingGaps(blueprint),
        isEmpty,
        reason: 'gap 16 > maxGap (${checks.maxGap})',
      );
    });

    test('a repeated number is a duplicate caption problem, not a gap', () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 48,
            caption: 'Export Lecturer',
            printedPage: 107,
            pdfPageIndex: 106,
            sectionId: 'C',
          ),
          _table(
            number: 48,
            caption: 'Export Lecturer again',
            printedPage: 108,
            pdfPageIndex: 107,
            sectionId: 'C',
          ),
        ],
      );
      expect(checks.numberingGaps(blueprint), isEmpty);
    });
  });

  group('missing sections', () {
    test('a complete outline reports nothing', () {
      expect(checks.missingSections(_blueprint()), isEmpty);
    });

    test('a report with no requirements chapter is high severity', () {
      final findings = checks.missingSections(
        _blueprint(sections: _fullOutline.sublist(0, 2)),
      );

      final srsMissing = findings.firstWhere(
        (f) => f.subject == 'Software Requirement Specification',
      );
      expect(srsMissing.severity, Severity.high);
      expect(srsMissing.check, CheckId.missingSection);
    });

    test('the other absent parts are medium severity', () {
      // Frame speaks: Introduction + SRS present, B/D/E absent.
      final findings = checks.missingSections(
        _blueprint(
          sections: [_fullOutline[0], _fullOutline[2]],
        ),
      );

      expect(findings, hasLength(3));
      expect(findings.every((f) => f.severity == Severity.medium), isTrue);
    });

    test('a document in a different frame is not judged at all', () {
      // None of the expected titles appear: this report simply has its own
      // structure, and telling it five parts are "missing" would be noise.
      final blueprint = _blueprint(
        sections: const [
          SectionRange(
            id: 'A',
            title: 'Overview of the Platform',
            printedStart: 1,
            printedEnd: 5,
            pdfStartIndex: 0,
            pdfEndIndex: 4,
          ),
          SectionRange(
            id: 'B',
            title: 'Functional Catalog',
            printedStart: 6,
            printedEnd: 30,
            pdfStartIndex: 5,
            pdfEndIndex: 29,
          ),
        ],
      );
      expect(checks.missingSections(blueprint), isEmpty);
    });

    test('one matching part alone does not activate the frame', () {
      // "Introduction" appears in almost every document; one word is not the
      // frame speaking.
      final blueprint = _blueprint(
        sections: const [
          SectionRange(
            id: 'A',
            title: 'Introduction',
            printedStart: 1,
            printedEnd: 5,
            pdfStartIndex: 0,
            pdfEndIndex: 4,
          ),
          SectionRange(
            id: 'B',
            title: 'Our Feature List',
            printedStart: 6,
            printedEnd: 30,
            pdfStartIndex: 5,
            pdfEndIndex: 29,
          ),
        ],
      );
      expect(checks.missingSections(blueprint), isEmpty);
    });

    test('the frame is a parameter, not a constant', () {
      const customChecks = BlueprintChecks(
        expectedSections: [
          ExpectedSection('API Reference', r'api reference', Severity.high),
          ExpectedSection('Changelog', r'changelog', Severity.medium),
        ],
      );
      final blueprint = _blueprint(
        sections: const [
          SectionRange(
            id: 'A',
            title: 'API Reference',
            printedStart: 1,
            printedEnd: 20,
            pdfStartIndex: 0,
            pdfEndIndex: 19,
          ),
          SectionRange(
            id: 'B',
            title: 'Architecture Guide',
            printedStart: 21,
            printedEnd: 40,
            pdfStartIndex: 20,
            pdfEndIndex: 39,
          ),
        ],
      );
      final findings = customChecks.missingSections(blueprint);

      expect(findings, hasLength(1));
      expect(findings.single.subject, 'Changelog');
    });

    test('an unreadable outline is not judged at all', () {
      expect(checks.missingSections(_blueprint(sections: [])), isEmpty);
    });
  });

  group('unclassified figures', () {
    test('a caption that names no diagram kind is a hint, not an error', () {
      final findings = checks.unclassifiedFigures(
        _blueprint(
          artifacts: [
            _figure(
              number: 4,
              caption: '<Student> Raise hand',
              printedPage: 28,
              pdfPageIndex: 27,
              sectionId: 'C',
            ),
          ],
        ),
      );

      expect(findings, hasLength(1));
      expect(findings.single.severity, Severity.low);
      expect(findings.single.subject, 'Figure 4');
    });

    test('a classified figure is left alone', () {
      final findings = checks.unclassifiedFigures(
        _blueprint(
          artifacts: [
            _figure(
              number: 90,
              caption: 'ERD Diagram',
              printedPage: 180,
              pdfPageIndex: 179,
              sectionId: 'D',
            ),
          ],
        ),
      );
      expect(findings, isEmpty);
    });
  });

  group('stale index page numbers', () {
    DocumentBlueprint stale({required bool trusted}) => _blueprint(
      trusted: trusted,
      artifacts: [
        _table(
          number: 9,
          caption: 'Unauthorized Login',
          printedPage: 25,
          sectionId: 'C',
        ),
      ],
    );

    test('an entry the body does not confirm is reported', () {
      final findings = checks.captionPageMismatches(stale(trusted: true));

      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.captionPageMismatch);
      expect(findings.single.message, contains('trang 25'));
    });

    test('an untrusted page mapping is not blamed on the document', () {
      expect(checks.captionPageMismatches(stale(trusted: false)), isEmpty);
    });

    test('resolved entries are never reported', () {
      final blueprint = _blueprint(
        artifacts: [
          _table(
            number: 9,
            caption: 'Unauthorized Login',
            printedPage: 25,
            pdfPageIndex: 24,
            sectionId: 'C',
          ),
        ],
      );
      expect(checks.captionPageMismatches(blueprint), isEmpty);
    });
  });

  group('runAll', () {
    test('collects every family that fires', () {
      final blueprint = _blueprint(
        sections: _fullOutline.sublist(0, 2),
        artifacts: [
          _table(
            number: 22,
            caption: 'USE CASE - Create group',
            printedPage: 54,
            pdfPageIndex: 53,
            sectionId: 'B',
          ),
          _table(
            number: 23,
            caption: 'USE CASE – Create group',
            printedPage: 56,
            pdfPageIndex: 55,
            sectionId: 'B',
          ),
          _figure(
            number: 4,
            caption: '<Student> Raise hand',
            printedPage: 28,
            sectionId: 'B',
          ),
        ],
      );
      final families = checks.runAll(blueprint).map((f) => f.check).toSet();

      expect(families, contains(CheckId.duplicateCaption));
      expect(families, contains(CheckId.missingSection));
      expect(families, contains(CheckId.unclassifiedFigure));
      expect(families, contains(CheckId.captionPageMismatch));
      expect(
        checks.runAll(blueprint).every((f) => f.check.isBlueprintCheck),
        isTrue,
      );
    });
  });
}
