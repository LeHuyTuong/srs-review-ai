import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/header_footer_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;

/// One furniture-bearing page: a running header, three body lines and the
/// page number extraction puts last. Five readable lines is exactly the
/// [HeaderFooterChecks] floor for a page to be sampled.
String _page(String header, int number) => [
  header,
  'Body line one',
  'Body line two',
  'Body line three',
  'Page $number',
].join('\n');

SrsDocument _document(List<String> pages) => SrsDocument(
  fileName: 'furniture.pdf',
  pageCount: pages.length,
  pageTexts: pages,
  requirements: const [],
);

void main() {
  const checks = HeaderFooterChecks();

  group('coverPageInfo', () {
    test('FPT-style cover with all three labels produces no finding', () {
      final document = _document(const [
        'Capstone Project Report\nProject name: OTES\nSupervisor: Nguyen '
            'Van A\nGroup 1\nStudent: Tran B',
        'Signature page',
      ]);
      expect(checks.coverPageInfo(document), isEmpty);
    });

    test('Vietnamese cover passes on folded labels (Đề tài / GVHD)', () {
      final document = _document(const [
        'Đề tài: Hệ thống thi trực tuyến\nGiảng viên hướng dẫn: Nguyễn Văn '
            'A\nNhóm 1\nThành viên: Trần B',
        'Trang ký tên',
      ]);
      expect(checks.coverPageInfo(document), isEmpty);
    });

    test('missing supervisor yields one medium finding on that subject', () {
      final document = _document(const [
        'Project name: OTES\nGroup 1\nStudent: Tran B\nSome other line\n'
            'And one more',
        'Signature page',
      ]);
      final findings = checks.coverPageInfo(document);
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.coverPageInfo);
      expect(findings.single.subject, 'supervisor');
      expect(findings.single.severity, Severity.medium);
      expect(findings.single.ledgerKey, 'cover_page_info:supervisor');
    });

    test('a scanned cover (no usable text layer) stays silent', () {
      final document = _document(const ['OTES 2020', '']);
      expect(checks.coverPageInfo(document), isEmpty);
    });
  });

  group('headerFooterConsistency', () {
    test('a stable running header across pages produces no finding', () {
      final document = _document([
        for (var i = 0; i < 10; i++)
          _page('Online Tutoring Examination System', i + 1),
      ]);
      expect(checks.headerFooterConsistency(document), isEmpty);
    });

    test('two header variants differing in a word are reported', () {
      final document = _document([
        for (var i = 0; i < 5; i++)
          _page('Online Tutoring Examination System', i + 1),
        for (var i = 5; i < 10; i++)
          _page('Online Testing Examination System', i + 1),
      ]);
      final findings = checks.headerFooterConsistency(document);
      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.check, CheckId.headerFooterConsistency);
      // Never above info/low: chapter-varying running heads are the known
      // false positive, so the finding must not read as a verdict.
      expect(finding.severity, Severity.low);
      expect(finding.messageVi, contains('Online Tutoring Examination System'));
      expect(finding.messageVi, contains('Online Testing Examination System'));
      expect(finding.messageVi, contains('tutoring'));
      expect(finding.subject, 'header_1:tutoring~testing');
      expect(
        finding.ledgerKey,
        'header_footer_consistency:header_1:tutoring~testing',
      );
    });

    test('variants differing only in digits are numbering, not a finding', () {
      final document = _document([
        for (var i = 0; i < 5; i++) _page('Capstone Project Report 2', i + 1),
        for (var i = 5; i < 10; i++) _page('Capstone Project Report 3', i + 1),
      ]);
      expect(checks.headerFooterConsistency(document), isEmpty);
    });

    test('page-number-only running heads are filtered out', () {
      final document = _document([
        for (var i = 0; i < 10; i++) _page('Page ${i + 1}', i + 1),
      ]);
      expect(checks.headerFooterConsistency(document), isEmpty);
    });

    test('short documents and image pages stay silent', () {
      // Below the 6-page floor: nothing to judge.
      final short = _document([
        for (var i = 0; i < 5; i++) _page('Online Tutoring System', i + 1),
      ]);
      expect(checks.headerFooterConsistency(short), isEmpty);

      // Image pages (fewer than 5 readable lines) are not sampled, so two
      // headers that never coexist on sampled pages cannot pair up.
      final withImages = _document([
        for (var i = 0; i < 6; i++) _page('Online Tutoring System', i + 1),
        for (var i = 0; i < 2; i++) 'Figure 1\ncaption',
      ]);
      expect(checks.headerFooterConsistency(withImages), isEmpty);
    });
  });
}
