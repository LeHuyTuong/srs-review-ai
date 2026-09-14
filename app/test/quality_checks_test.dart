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

  group('missingPriority (criterion 7, document-level)', () {
    test('fires once when no requirement mentions a priority', () {
      final findings = checks.run(
        _doc([
          _item('UC-01', 'The system shall allow students to log in.'),
          _item('UC-02', 'The system shall store exam results.'),
        ]),
      );
      final rows = findings
          .where((f) => f.check == CheckId.missingPriority)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.passed, isFalse);
      expect(rows.single.message, contains('criterion 7'));
    });

    test('passes when any row names a priority field', () {
      final findings = checks.run(
        _doc([
          _item('UC-01', 'plain text here with no metadata.'),
          _item(
            'UC-02',
            'Author: someone. Priority: normal. Actor: admin.',
          ),
        ]),
      );
      final row = findings
          .where((f) => f.check == CheckId.missingPriority)
          .single;
      expect(row.passed, isTrue);
    });

    test('the Vietnamese template form passes on folded text (NFD too)', () {
      // "Độ ưu tiên" is the field name in Vietnamese SRS templates;
      // NFD vs NFC must not change the verdict (text_fold contract).
      final nfc = checks.run(
        _doc([
          _item(
            'UC-01',
            'Độ ưu tiên: Cao. The system allows login as well.',
          ),
        ]),
      );
      final nfd = checks.run(
        _doc([
          _item(
            'UC-01',
            'Do\u0323\u0303 u\u031Bu tie\u0302n: Cao. An ASCII tail for length.',
          ),
        ]),
      );
      expect(
        nfc.where((f) => f.check == CheckId.missingPriority).single.passed,
        isTrue,
      );
      expect(
        nfd.where((f) => f.check == CheckId.missingPriority).single.passed,
        isTrue,
      );
    });

    test('empty document emits no priority row', () {
      final findings = checks.run(_doc(const []));
      expect(
        findings.where((f) => f.check == CheckId.missingPriority),
        isEmpty,
      );
    });
  });
}
