import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/deterministic_checks/checks/syllabus_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart';

SrsDocument _documentWith(List<RequirementItem> requirements) => SrsDocument(
  fileName: 'test.pdf',
  pageCount: 1,
  pageTexts: const ['irrelevant'],
  requirements: requirements,
);

List<RequirementItem> _useCases(
  int count, {
  String text = 'The user clicks submit and saves.',
}) => List.generate(
  count,
  (i) => RequirementItem(
    id: 'UC-${i + 1}',
    text: text,
    kind: RequirementKind.useCase,
  ),
);

void main() {
  const checks = SyllabusChecks(RubricConfig.fallback);

  group('F7 use case count', () {
    test(
      'flags a document below the 20 use case defense gate as high severity',
      () {
        final finding = checks.useCaseCount(_documentWith(_useCases(12)));

        expect(finding.passed, isFalse);
        expect(finding.severity, Severity.high);
        expect(finding.actual, 12);
        expect(finding.expectedMin, 20);
      },
    );

    test('passes at or above the 20 use case minimum', () {
      final finding = checks.useCaseCount(_documentWith(_useCases(22)));

      expect(finding.passed, isTrue);
    });

    test('treats a boundary count of exactly 20 as passing', () {
      expect(checks.useCaseCount(_documentWith(_useCases(20))).passed, isTrue);
    });

    // Rubric v3 / rulebook 1.5 Q1 dropped the ceiling of 25. This is the
    // OTES case: 63 use cases used to fail here, while the real defect —
    // 45 of them holding a single transaction — was F9's to report and got
    // buried behind a count warning nobody could act on.
    test('a large count is not a defect — 63 use cases pass', () {
      final finding = checks.useCaseCount(_documentWith(_useCases(63)));

      expect(finding.passed, isTrue);
      expect(finding.severity, Severity.low);
      expect(finding.expectedMax, isNull);
    });

    test('ignores non use case requirements when counting', () {
      final document = _documentWith([
        ..._useCases(3),
        const RequirementItem(
          id: 'FR-01',
          text: 'The system shall do a thing.',
          kind: RequirementKind.functional,
        ),
      ]);

      expect(checks.useCaseCount(document).actual, 3);
    });
  });

  group('F8 English only', () {
    test('flags a Vietnamese requirement', () {
      final findings = checks.language(
        _documentWith([
          const RequirementItem(
            id: 'FR-01',
            text:
                'Hệ thống phải cho phép người dùng tải lên tài liệu và xem kết quả.',
            kind: RequirementKind.functional,
          ),
        ]),
      );

      expect(findings.single.passed, isFalse);
      expect(findings.single.subject, 'FR-01');
      expect(findings.single.severity, Severity.medium);
    });

    test('accepts English requirements', () {
      final findings = checks.language(
        _documentWith([
          const RequirementItem(
            id: 'FR-01',
            text:
                'The system shall allow the user to upload a document and view the result.',
            kind: RequirementKind.functional,
          ),
        ]),
      );

      expect(findings.single.passed, isTrue);
    });

    test('detects Vietnamese written without diacritics via stopwords', () {
      expect(
        LanguageDetector.looksEnglish(
          'He thong phai cho phep nguoi dung tai len tai lieu',
        ),
        isFalse,
      );
    });

    test('detects NFD-decomposed Vietnamese (the OTES normalization trap)', () {
      // Same sentence with combining marks instead of precomposed
      // letters: before the fold, the splitter shredded these words
      // into letter fragments and the text passed as English.
      expect(
        LanguageDetector.looksEnglish(
          'H\u1EC7 th\u006F\u0301ng phai cho phep ngu\u006F\u0303i dung tai len tai li\u1EC7u',
        ),
        isFalse,
      );
    });

    test('English metadata with a Vietnamese author name still passes', () {
      // Proven shape from the real OTES: every failing row before the
      // proper-noun rule was an English use-case table whose Author cell
      // held a Vietnamese name. Names must not fail the row.
      expect(
        LanguageDetector.looksEnglish(
          'Use case name Login. Author: Nguyễn Minh Hiểu. '
          'Actor: Student. Summary: this use case allows a user to sign in.',
        ),
        isTrue,
      );
    });

    test('does not flag very short strings', () {
      expect(LanguageDetector.looksEnglish('UC-01'), isTrue);
    });
  });

  group('F9 use case size', () {
    test('flags a use case that is too thin', () {
      final findings = checks.useCaseSizes(
        _documentWith([
          const RequirementItem(
            id: 'UC-01',
            text: 'View profile.',
            kind: RequirementKind.useCase,
          ),
        ]),
      );

      expect(findings.single.passed, isFalse);
      expect(findings.single.subject, 'UC-01');
      expect(findings.single.actual, lessThan(3));
    });

    test('accepts a medium use case of 3-7 transactions', () {
      final findings = checks.useCaseSizes(
        _documentWith([
          const RequirementItem(
            id: 'UC-02',
            text:
                'The user clicks Search, enters a keyword, and the system saves the query.',
            kind: RequirementKind.useCase,
          ),
        ]),
      );

      expect(findings, isEmpty);
    });

    test('flags an oversized use case', () {
      final findings = checks.useCaseSizes(
        _documentWith([
          const RequirementItem(
            id: 'UC-03',
            text:
                '1. login 2. search 3. select 4. edit 5. save 6. export 7. confirm 8. logout',
            kind: RequirementKind.useCase,
          ),
        ]),
      );

      expect(findings.single.passed, isFalse);
      expect(findings.single.actual, greaterThan(7));
    });

    test('prefers an explicit numbered main flow over keyword counting', () {
      expect(
        TransactionCounter.count(
          '1. The user opens the page 2. clicks save 3. sees a message',
        ),
        3,
      );
    });

    // Regression: RequirementSplitter joins lines with a single space
    // (`buffer.join(' ')`), so a Step/Actor Action/System Response table
    // whose cells were each their own line — the real shape of a Word
    // use-case table once flattened to text — reads as "1 User goes ..."
    // with NO period after the digit, not "1. User goes ...". Verified
    // against a real capstone SRS (OTES) via pdftotext.
    test('counts a numbered flow flattened from a table (no period)', () {
      expect(
        TransactionCounter.count(
          'Step Actor Action System Response '
          '1 User goes to the login view. The system sends a login command. '
          '2 User inputs information. '
          '3 User sends command to login to system',
        ),
        3,
      );
    });

    test('counts Vietnamese action cues too', () {
      expect(
        TransactionCounter.count(
          'Người dùng nhấn nút, nhập dữ liệu và lưu thông tin',
        ),
        greaterThanOrEqualTo(3),
      );
    });
  });

  test('runAll returns one finding per check family', () {
    final findings = checks.runAll(_documentWith(_useCases(21)));

    expect(findings.any((f) => f.check == CheckId.ucCount), isTrue);
    expect(findings.any((f) => f.check == CheckId.language), isTrue);
  });
}
