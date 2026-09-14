// Deterministic subset of the srs-writer skill's quality checklist.
// Fixtures are bilingual on purpose: the checker that only speaks English
// fails silently on the Vietnamese documents this app actually reviews
// (AGENTS.md: verify scripts must match the document language).
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/quality_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart' show Severity;
import 'package:srs_review_ai/data/models/srs_document.dart';

RequirementItem _item(String id, String text) => RequirementItem(
  id: id,
  text: text,
  kind: RequirementKind.statement,
  pageIndex: 1,
);

SrsDocument _doc(List<RequirementItem> items) => SrsDocument(
  fileName: 'a.pdf',
  pageCount: 2,
  pageTexts: const [],
  requirements: items,
);

void main() {
  const checks = QualityChecks();

  group('ambiguousWording', () {
    test('flags English vague phrases with word boundaries', () {
      final findings = checks.run(
        _doc([
          _item('FR-01', 'The system shall be user-friendly and fast.'),
          _item('FR-02', 'The connector shall be secured with a latch.'),
        ]),
      ).where((f) => f.check == CheckId.ambiguousWording);
      // "user-friendly" and "fast" hit; "secured" must NOT match "secure"
      // because of the word boundary.
      expect(findings, hasLength(1));
      expect(findings.single.subject, 'FR-01');
      expect(findings.single.message, contains('"user-friendly"'));
      expect(findings.single.message, contains('"fast"'));
      expect(findings.single.severity, Severity.low);
    });

    test('flags Vietnamese phrases — the OTES language', () {
      final findings = checks.run(
        _doc([
          _item(
            'UC01',
            'Hệ thống phản hồi nhanh chóng và hiển thị thông báo '
                'phù hợp với từng vai trò.',
          ),
        ]),
      ).where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('"nhanh chóng"'));
      expect(findings.single.message, contains('"phù hợp"'));
    });

    test('"v.v." is caught, "vv" without dots is not (conservative)', () {
      final findings = checks.run(
        _doc([
          _item('FR-03', 'Mô tả các trường: tên, mã, ngày bắt đầu, v.v.'),
        ]),
      ).where((f) => f.check == CheckId.ambiguousWording);
      expect(findings.single.message, contains('"v.v."'));
    });

    test('NFD-decomposed Vietnamese is caught too (the real OTES form)', () {
      // "chong" written with a raw combining acute — the mixed-
      // normalization shape the probe found in the real document.
      final findings = checks.run(
        _doc([
          _item('FR-08', 'H\u1EC7 th\u1ED1ng ph\u1EA3n h\u1ED3i nhanh ch\u006F\u0301ng.'),
        ]),
      ).where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('"nhanh ch\u00F3ng"'));
    });

    test('clean document yields one passing row, not silence', () {
      final findings = checks.run(
        _doc([
          _item(
            'FR-04',
            'The system shall return search results within 2 seconds '
                'for the 95th percentile under 10000-record load.',
          ),
        ]),
      ).where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.passed, isTrue);
    });
  });

  group('placeholderTbd', () {
    test('flags English and Vietnamese placeholders at medium severity', () {
      final findings = checks.run(
        _doc([
          _item('FR-05', 'Retention period: TBD.'),
          _item('FR-06', 'Thời gian xử lý: chưa xác định.'),
        ]),
      ).where((f) => f.check == CheckId.placeholderTbd);
      expect(findings, hasLength(2));
      expect(findings.map((f) => f.subject), containsAll(['FR-05', 'FR-06']));
      expect(findings.first.severity, Severity.medium);
    });

    test('no placeholder yields one passing row', () {
      final findings = checks.run(
        _doc([_item('FR-07', 'Retention period: 90 days.')]),
      ).where((f) => f.check == CheckId.placeholderTbd);
      expect(findings.single.passed, isTrue);
    });
  });

  test('empty document yields no rows at all (nothing to claim)', () {
    expect(checks.run(_doc(const [])), isEmpty);
  });
}
