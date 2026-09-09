import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/checks/syllabus_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';

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

    test('passes inside the recommended 20-25 range', () {
      final finding = checks.useCaseCount(_documentWith(_useCases(22)));

      expect(finding.passed, isTrue);
    });

    test('treats a boundary count of exactly 20 as passing', () {
      expect(checks.useCaseCount(_documentWith(_useCases(20))).passed, isTrue);
    });

    test(
      'warns only mildly above 25 — more scope is allowed, just unusual',
      () {
        final finding = checks.useCaseCount(_documentWith(_useCases(30)));

        expect(finding.passed, isFalse);
        expect(finding.severity, Severity.low);
      },
    );

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
