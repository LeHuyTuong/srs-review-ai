// Deterministic subset of the srs-writer skill's quality checklist.
// Fixtures are bilingual on purpose: the checker that only speaks English
// fails silently on the Vietnamese documents this app actually reviews
// (AGENTS.md: verify scripts must match the document language).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/quality_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;

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
      final findings = checks
          .run(
            _doc([
              _item('FR-01', 'The system shall be user-friendly and fast.'),
              _item('FR-02', 'The connector shall be secured with a latch.'),
            ]),
          )
          .where((f) => f.check == CheckId.ambiguousWording);
      // "user-friendly" and "fast" hit; "secured" must NOT match "secure"
      // because of the word boundary.
      expect(findings, hasLength(1));
      expect(findings.single.subject, 'FR-01');
      expect(findings.single.messageEn, contains('"user-friendly"'));
      expect(findings.single.messageEn, contains('"fast"'));
      expect(findings.single.severity, Severity.low);
    });

    test('flags Vietnamese phrases — the OTES language', () {
      final findings = checks
          .run(
            _doc([
              _item(
                'UC01',
                'Hệ thống phản hồi nhanh chóng và hiển thị thông báo '
                    'phù hợp với từng vai trò.',
              ),
            ]),
          )
          .where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.messageEn, contains('"nhanh chóng"'));
      expect(findings.single.messageEn, contains('"phù hợp"'));
    });

    test('"v.v." is caught, "vv" without dots is not (conservative)', () {
      final findings = checks
          .run(
            _doc([
              _item('FR-03', 'Mô tả các trường: tên, mã, ngày bắt đầu, v.v.'),
            ]),
          )
          .where((f) => f.check == CheckId.ambiguousWording);
      expect(findings.single.messageEn, contains('"v.v."'));
    });

    test('NFD-decomposed Vietnamese is caught too (the real OTES form)', () {
      // "chong" written with a raw combining acute — the mixed-
      // normalization shape the probe found in the real document.
      final findings = checks
          .run(
            _doc([
              _item(
                'FR-08',
                'H\u1EC7 th\u1ED1ng ph\u1EA3n h\u1ED3i nhanh ch\u006F\u0301ng.',
              ),
            ]),
          )
          .where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.messageEn, contains('"nhanh ch\u00F3ng"'));
    });

    test('clean document yields one passing row, not silence', () {
      final findings = checks
          .run(
            _doc([
              _item(
                'FR-04',
                'The system shall return search results within 2 seconds '
                    'for the 95th percentile under 10000-record load.',
              ),
            ]),
          )
          .where((f) => f.check == CheckId.ambiguousWording);
      expect(findings, hasLength(1));
      expect(findings.single.passed, isTrue);
    });
  });

  group('placeholderTbd', () {
    test('flags English and Vietnamese placeholders at medium severity', () {
      final findings = checks
          .run(
            _doc([
              _item('FR-05', 'Retention period: TBD.'),
              _item('FR-06', 'Thời gian xử lý: chưa xác định.'),
            ]),
          )
          .where((f) => f.check == CheckId.placeholderTbd);
      expect(findings, hasLength(2));
      expect(findings.map((f) => f.subject), containsAll(['FR-05', 'FR-06']));
      expect(findings.first.severity, Severity.medium);
    });

    test('no placeholder yields one passing row', () {
      final findings = checks
          .run(_doc([_item('FR-07', 'Retention period: 90 days.')]))
          .where((f) => f.check == CheckId.placeholderTbd);
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
      expect(rows.single.messageEn, contains('criterion 7'));
    });

    test('passes when any row names a priority field', () {
      final findings = checks.run(
        _doc([
          _item('UC-01', 'plain text here with no metadata.'),
          _item('UC-02', 'Author: someone. Priority: normal. Actor: admin.'),
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
          _item('UC-01', 'Độ ưu tiên: Cao. The system allows login as well.'),
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

  // Rulebook 1.5 hard rule 6. Both halves are required — that is the whole
  // point of the check, and each test below isolates one half.
  group('nfrUnquantified (rulebook hard rule 6)', () {
    Iterable<DeterministicFinding> nfr(List<RequirementItem> items) => checks
        .run(_doc(items))
        .where((f) => f.check == CheckId.nfrUnquantified);

    test('passes an NFR with both a figure and a measurement condition', () {
      final finding = nfr([
        _item(
          'NFR-PERF-01',
          'The search page shall respond within 2 s at the 95th percentile.',
        ),
      ]).single;

      expect(finding.passed, isTrue);
      expect(finding.severity, Severity.low);
    });

    test('flags an NFR with no figure at all as high severity', () {
      final finding = nfr([
        _item('NFR-RELI-01', 'The system shall be available at all times.'),
      ]).single;

      expect(finding.passed, isFalse);
      expect(finding.severity, Severity.high);
    });

    test('flags a figure with no condition — the half documents omit', () {
      final finding = nfr([
        _item('NFR-PERF-02', 'Response time is 2 s.'),
      ]).single;

      expect(finding.passed, isFalse);
      expect(finding.messageEn, contains('not the condition'));
    });

    // The trap a plain digit scan falls into: standards references and
    // section numbers are digits that measure nothing.
    test('a standards reference is not a measurable figure', () {
      final finding = nfr([
        _item(
          'NFR-SECU-01',
          'Security shall follow ISO 25010 and section 3.2 of the policy.',
        ),
      ]).single;

      expect(finding.passed, isFalse);
    });

    test(
      'recognises an NFR by section wording when the id does not say so',
      () {
        final findings = nfr([
          _item('R-09', 'Performance: the report builds in under 5 min.'),
        ]);

        expect(findings, hasLength(1));
        expect(findings.single.passed, isTrue);
      },
    );

    test('functional requirements are not measured here', () {
      expect(
        nfr([_item('FR-AUTH-01', 'The system shall let a user log in.')]),
        isEmpty,
      );
    });

    // A use case narrating a security step is describing a flow, not
    // stating a quality target. Charging it a high-severity NFR finding is
    // the false positive that gets a checker switched off.
    test('a use case mentioning a quality word is not an NFR', () {
      final useCase = RequirementItem(
        id: 'UC-004',
        text:
            'Security: the actor enters a password and the system verifies '
            'it against the stored hash.',
        kind: RequirementKind.useCase,
        pageIndex: 1,
      );

      expect(nfr([useCase]), isEmpty);
    });
  });

  // Guards the drift the schema's own description warns about: a CheckId
  // added in Dart but not in contracts/review.schema.json ships a wire value
  // no consumer of the contract knows about.
  test('every CheckId wire value is listed in the contract schema', () {
    final schema =
        jsonDecode(File('../contracts/review.schema.json').readAsStringSync())
            as Map<String, dynamic>;
    final listed =
        ((schema[r'$defs'] as Map)['CheckId'] as Map)['enum'] as List;

    expect(
      listed.cast<String>(),
      unorderedEquals(CheckId.values.map((c) => c.wire).toList()),
    );
  });
}
