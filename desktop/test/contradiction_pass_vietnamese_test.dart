/// Plan 9 P1 — chain 1 was ASCII-only, so a Vietnamese SRS produced a FALSE
/// ZERO: `r13_otes_deterministic_ceiling.md:29` recorded `crossArtifactName` = 0
/// on OTES. Read literally that says "this document is clean"; what it actually
/// said was "this check cannot read Vietnamese at all".
///
/// What a probe established BEFORE these tests were written (measure, then
/// assert — never the other way round):
///
///   'Customer registers' -> original=[Customer]   stem=[customer]
///   'Customers book'     -> original=[Customers]  stem=[customer]   <- fires
///   'Sinhvien'           -> original=[Sinhvien]   stem=[sinhvien]
///   'Sinhviens'          -> original=[Sinhviens]  stem=[sinhvien]   <- fires
///   'Lớp' / 'Lớps'      -> stem=[lớp] both, VI plural still collapses
///   'Sinh viên xem'      -> original=[Sinh]       stem=[sinh]       (truncated)
///   'Khách hàng đăng ký' -> original=[Khách]      stem=[khách]
///
/// So the check fires when two DIFFERENT original strings share one stem, and
/// it only sees the leading capitalised run — an internal capital ("SinhVien")
/// truncates it. Both limits are pinned by tests below rather than left for
/// someone to discover in a report.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/contradiction_pass.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';

SrsDocument docOf(List<(String, String)> rows) => SrsDocument(
  fileName: 'otes.docx',
  pageCount: 1,
  pageTexts: const [''],
  requirements: [
    for (var i = 0; i < rows.length; i++)
      RequirementItem(
        id: 'R$i',
        text: rows[i].$1,
        section: rows[i].$2,
        kind: RequirementKind.statement,
      ),
  ],
);

void main() {
  const pass = ContradictionPass();

  group('chain 1 reads Vietnamese now (AC4)', () {
    test('a Vietnamese concept written two ways IS reported', () {
      // The old ASCII-only pattern matched nothing in either string, so this
      // exact shape returned [] and was recorded as "0 findings".
      final findings = pass.detect(
        docOf([('Sinhvien', '3.1'), ('Sinhviens', '4.2')]),
      );
      expect(
        findings,
        hasLength(1),
        reason: 'a Vietnamese naming drift must be reported, not silently zero',
      );
      expect(findings.first.check.wire, 'cross_artifact_name');
      // Text alone cannot prove two labels mean one concept, so the row stays
      // PENDING-VISION: nobody is told to "fix" a name that never varied.
      expect(findings.first.requiresVisionEvidence, isTrue);
    });

    test('English is unchanged (the fix is not a regression)', () {
      final findings = pass.detect(
        docOf([
          ('Customer registers a course', '3.1'),
          ('Customers book a room', '4.2'),
        ]),
      );
      expect(findings, hasLength(1));
      expect(findings.first.check.wire, 'cross_artifact_name');
    });
  });

  group('the limits, pinned so nobody assumes them', () {
    test('a clean Vietnamese document stays silent (no false alarm)', () {
      // Bilingual matching must not fire on every Vietnamese sentence, or the
      // check becomes noise reviewers learn to ignore.
      final findings = pass.detect(
        docOf([
          ('Sinhvien đăng ký học phần', '3.1'),
          ('Giáo viên duyệt đơn', '3.2'),
          ('Hệ thống gửi email', '4.1'),
        ]),
      );
      expect(findings, isEmpty);
    });

    test('a diacritic-only difference is NOT a match', () {
      // Pinned on purpose: stemOf does not fold diacritics, so "Khách" and
      // "Khach" are two names to it. Writing this is what turns that from an
      // accident into a decision.
      final findings = pass.detect(
        docOf([('Khách hàng đăng ký', '3.1'), ('Khach hàng đặt lại', '4.2')]),
      );
      expect(findings, isEmpty, reason: 'diacritic folding is out of scope');
    });

    test('an internal capital truncates the name it reads', () {
      // "SinhVien" is read as "Sinh" — the probe measured it. Pinned so the
      // truncation is a known number, not a surprise in a real report.
      final findings = pass.detect(
        docOf([('Sinh viên đăng ký', '3.1'), ('SinhVien xem điểm', '4.2')]),
      );
      expect(findings, isEmpty);
    });
  });
}
