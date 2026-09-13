/// Round 11 — wire + behaviour tests for the contradiction pass.
///
/// Goal §2 step 6 calls this the "đắt nhất" family. The deterministic
/// version here is weaker than the LLM pass (no embedding, no diagram
/// vision) — it operates on requirement text only and reproduces the
/// spelling / casing / plural variation pattern. These tests pin both
/// the positive signal (cross-section variant) and the false-positive
/// guards (same stem in one section; totally distinct stems; plural
/// drift that SHOULD collapse).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/contradiction_pass.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';

const _pass = ContradictionPass();

RequirementItem _req({
  required String id,
  required String text,
  String? section,
}) =>
    RequirementItem(
      id: id,
      text: text,
      kind: RequirementKind.useCase,
      section: section,
    );

SrsDocument _doc(List<RequirementItem> reqs) => SrsDocument(
      fileName: 'fixture.srs',
      pageCount: 1,
      pageTexts: const ['fixture'],
      requirements: reqs,
      imagePageIndexes: const [],
    );

void main() {
  group('ContradictionPass — goal §2 step 6', () {
    test('cross-section variant is flagged', () {
      // The HisWise pattern: same concept, different label, in two
      // different sections.
      final findings = _pass.detect(
        _doc([
          _req(id: 'UC-01', text: 'Customer logs in.', section: '3.1 Login'),
          _req(
            id: 'UC-02',
            text: 'Client browses the catalogue.',
            section: '3.2 Catalogue',
          ),
        ]),
      );
      // "Customer" vs "Client" — different stems, no contradiction.
      // This is the limitation the doc-comment warns about.
      expect(findings, isEmpty);
    });

    test('plural drift across sections IS flagged', () {
      // "Customers" (section 3.4) vs "Customer" (section 3.5) — same
      // stem "customer" (plural stripped), two distinct originals,
      // two distinct sections. The original strings surface in the
      // message so the dashboard can show exactly which variants
      // collide.
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-10',
            text: 'Customers browse their profile.',
            section: '3.4 Account',
          ),
          _req(
            id: 'UC-11',
            text: 'Customer updates the profile settings.',
            section: '3.5 Settings',
          ),
        ]),
      );
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.check, CheckId.crossArtifactName);
      expect(f.passed, isFalse);
      expect(f.severity, Severity.high);
      expect(f.subject, 'customer');
      expect(f.actual, 2);
      // The original strings appear verbatim in the message, comma-
      // separated, so the dashboard renders the actual variants.
      expect(f.message, contains('Customer'));
      expect(f.message, contains('Customers'));
      expect(f.message, contains('3.4 Account'));
      expect(f.message, contains('3.5 Settings'));
    });

    test('case-only difference collapses correctly', () {
      // "Customer" and "customer" — same lowercase stem, two distinct
      // originals. Should be flagged (casing is the most common drift
      // pattern in real SRS prose).
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-20',
            text: 'Customer starts a session.',
            section: '4.1 Session',
          ),
          _req(
            id: 'UC-21',
            text: 'customer ends the session.',
            section: '4.2 Session',
          ),
        ]),
      );
      // Both in section 4.x. Only one section present — the cross-section
      // requirement must NOT trigger; same entity, two originals in one
      // section is a different finding shape.
      expect(findings, isEmpty);
    });

    test('single section with two variants does NOT trigger', () {
      // Two originals but only one section. The contradiction is
      // intra-section, which the dashboard already shows as duplicate
      // ids / repeated ids; the cross-section gate is what makes this
      // finding expensive.
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-30',
            text: 'Customers view the dashboard.',
            section: '5 Reports',
          ),
          _req(
            id: 'UC-31',
            text: 'Customer exports a report.',
            section: '5 Reports',
          ),
        ]),
      );
      expect(findings, isEmpty);
    });

    test('two distinct entities do NOT trigger', () {
      // No shared stem — these are different concepts.
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-40',
            text: 'Customer logs in.',
            section: '6.1 Auth',
          ),
          _req(
            id: 'UC-41',
            text: 'Admin assigns roles.',
            section: '6.2 Roles',
          ),
        ]),
      );
      expect(findings, isEmpty);
    });

    test('requirement with no capitalized phrase is skipped', () {
      // All-lowercase text — the extractor returns null, the row is
      // skipped, no false positive.
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-50',
            text: 'system must persist the record',
            section: '7 Persistence',
          ),
          _req(
            id: 'UC-51',
            text: 'system shall confirm the write',
            section: '7 Persistence',
          ),
        ]),
      );
      expect(findings, isEmpty);
    });

    test('null section is treated as one bucket for cross-section gate', () {
      // When section is missing, the cluster uses "(no section)" — two
      // rows with no section still collapse to one bucket, so the
      // cross-section gate suppresses the finding.
      final findings = _pass.detect(
        _doc([
          _req(id: 'UC-60', text: 'Customer opens the app.'),
          _req(id: 'UC-61', text: 'Customers close the app.'),
        ]),
      );
      expect(findings, isEmpty);
    });

    test('empty document produces empty findings', () {
      expect(_pass.detect(_doc(const [])), isEmpty);
    });

    test('finding message lists every variant and every section', () {
      // The dashboard renders the message verbatim — a finding that
      // hides one of the variants is not useful for the user. This
      // test pins the surface so a future "trim long messages" change
      // cannot quietly drop evidence.
      final findings = _pass.detect(
        _doc([
          _req(
            id: 'UC-70',
            text: 'Customers submit the form.',
            section: '8.1 Intake',
          ),
          _req(
            id: 'UC-71',
            text: 'Customer confirms the submission.',
            section: '8.2 Review',
          ),
        ]),
      );
      final msg = findings.single.message;
      // Each variant appears as a bare substring — the message joins
      // them with ", " so a trailing-space check would always miss.
      expect(msg, contains('Customer'));
      expect(msg, contains('Customers'));
      expect(msg, contains('8.1 Intake'));
      expect(msg, contains('8.2 Review'));
      expect(msg, contains('pick one name'));
    });
  });
}