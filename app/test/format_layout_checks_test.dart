/// §F.5a/F.5b — heading hierarchy and page-number presence, the two
/// format/layout criteria the text layer can answer honestly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/format_layout_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart' show Severity;
import 'package:srs_review_ai/data/models/srs_document.dart';

RequirementItem _section(String id) => RequirementItem(
  id: id,
  text: '$id Some heading text',
  kind: RequirementKind.section,
  pageIndex: 0,
);

/// pageTexts where page i (i ≥ 1) ends with [suffix]; the cover carries
/// none. Fewer than 6 pages total flips the §F.5b sample gate off.
List<String> _pages(int count, String? Function(int pageIndex) suffix) => [
  for (var i = 0; i < count; i++)
    i == 0
        ? 'Cover\nProject title'
        : 'Body line\n${suffix(i) ?? 'no number here'}',
];

void main() {
  const checks = FormatLayoutChecks();

  group('§F.5a headingNumbering', () {
    test('a complete hierarchy and unique numbers stay silent', () {
      final findings = checks.headingNumbering([
        _section('SEC-1'),
        _section('SEC-2'),
        _section('SEC-3'),
        _section('SEC-3.1'),
        _section('SEC-3.2'),
        _section('SEC-4'),
        _section('UC-01'), // not a numbered heading — ignored
        _section('SEC-overview'), // unnumbered heading — ignored
      ]);
      expect(findings, isEmpty);
    });

    test('a child without its parent fires once per missing level', () {
      final findings = checks.headingNumbering([
        _section('SEC-3'),
        _section('SEC-3.1'),
        // SEC-4 exists only as 4.2 / 4.2.1 — level 4 itself is missing.
        _section('SEC-4.2'),
        _section('SEC-4.2.1'),
      ]);
      expect(findings, hasLength(2));
      expect(findings.every((f) => f.check == CheckId.headingNumbering), isTrue);
      // Both fired rows name '4' as the missing parent, with the child as
      // the subject so the ledger can point at the offending heading.
      expect(
        findings.map((f) => f.subject),
        unorderedEquals(['SEC-4.2', 'SEC-4.2.1']),
      );
      expect(findings.every((f) => f.message.contains('"4"')), isTrue);
      expect(findings.every((f) => f.severity == Severity.medium), isTrue);
    });

    test('the same number used twice fires with the count', () {
      final findings = checks.headingNumbering([
        _section('SEC-3'),
        _section('SEC-3'),
      ]);
      expect(findings, hasLength(1));
      expect(findings.single.subject, 'SEC-3');
      expect(findings.single.message, contains('2 lần'));
    });

    test('1.10 after 1.9 is a normal increment, not a gap', () {
      final findings = checks.headingNumbering([
        _section('SEC-1'),
        _section('SEC-1.9'),
        _section('SEC-1.10'),
      ]);
      expect(findings, isEmpty);
    });
  });

  group('§F.5b pageNumbering', () {
    test('fewer than 6 pages is below the sample gate', () {
      expect(
        checks.pageNumbering(_pages(5, (i) => null)),
        isEmpty,
        reason: 'short documents often skip numbers by choice',
      );
    });

    test('a monotonic run of trailing numbers stays silent', () {
      expect(
        checks.pageNumbering(_pages(7, (i) => '${i + 1}')),
        isEmpty,
      );
      // The other footer shapes count too.
      expect(
        checks.pageNumbering(_pages(7, (i) => 'Trang ${i + 1}')),
        isEmpty,
      );
    });

    test('no page number anywhere fires one low finding', () {
      final findings = checks.pageNumbering(_pages(8, (i) => null));
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.pageNumbering);
      expect(findings.single.severity, Severity.low);
      expect(findings.single.message, contains('kiểm tra bằng mắt'));
    });

    test('a run that repeats or steps backwards fires once', () {
      final suffixes = ['2', '3', '3', '3', '5', '4'];
      final findings = checks.pageNumbering(
        _pages(7, (i) => suffixes[i - 1]),
      );
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.pageNumbering);
      expect(findings.single.message, contains('3 lần'));
    });
  });
}