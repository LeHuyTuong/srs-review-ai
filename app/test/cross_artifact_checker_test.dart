/// Chain 2 (FK matrix) — the cross-artifact join added in plan 9 P0b.
///
/// Every expected number was computed BY HAND from the rule text and written
/// down before the implementation was run against it. A test that recomputes
/// the formula with the same code proves nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/diagram_audit/services/cross_artifact_checker.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';

SrsDocument docOf(List<String> texts) => SrsDocument(
  fileName: 't.pdf',
  pageCount: 1,
  pageTexts: const [''],
  requirements: [
    for (var i = 0; i < texts.length; i++)
      RequirementItem(
        id: 'R$i',
        text: texts[i],
        kind: RequirementKind.statement,
      ),
  ],
);

DiagramRelationship rel(String from, String to, [String label = '']) =>
    DiagramRelationship(source: from, target: to, label: label);

ChainScore rowOf(ChainScore s) => s;

void main() {
  group('stemOf — one normaliser for both sides (AC2)', () {
    test('the four writing variants collapse to ONE key', () {
      // By hand: lowercase, trim, drop a trailing 's' per word.
      final keys = <String>{
        stemOf('Customer'),
        stemOf('Customers'),
        stemOf('CUSTOMER'),
        stemOf('Customer  '),
      };
      expect(keys, hasLength(1), reason: 'all four must be the same stem');
      expect(keys.single, 'customer');
    });

    test('multi-word names collapse the same way', () {
      expect(stemOf('Order Items'), stemOf('order  items'));
      expect(stemOf('Order Items'), 'order item');
    });

    test('a genuinely different name does NOT collapse', () {
      // The whole check is meaningless if these merged.
      expect(stemOf('Customer'), isNot(stemOf('Client')));
    });
  });

  group('scoreFkMatrix — the ratio from scoring.md:112 (AC3)', () {
    test('4 of 5 relationship labels appear in the text => 0.8', () {
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [
          rel('Customer', 'Order', 'place'),
          rel('Order', 'Item', 'contain'),
          rel('Customer', 'Address', 'own'),
          rel('Item', 'Category', 'belong'),
          rel('Order', 'Payment', 'settle'),
        ],
        // Text declares place, contain, own, belong — but never "settle".
        document: docOf([
          'A Customer can place an Order.',
          'An Order can contain an Item.',
          'A Customer can own an Address.',
          'An Item can belong to a Category.',
        ]),
      );
      expect(score.matched, 4.0);
      expect(score.total, 5.0);
      expect(score.ratio, closeTo(0.8, 1e-9));
      expect(score.unmatched, hasLength(1));
      expect(score.unmatched.single, contains('settle'));
    });

    test('an unlabelled relation leaves BOTH counts (not scored 0%)', () {
      // By hand: 2 labelled, 1 with no label. The unlabelled one cannot be
      // checked, so the denominator is 2 — not 3, and not 1/3.
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [
          rel('Customer', 'Order', 'place'),
          rel('Order', 'Item', 'contain'),
          rel('Item', 'Tag', ''),
        ],
        document: docOf(['A Customer can place an Order.', 'contain an Item.']),
      );
      expect(score.total, 2.0);
      expect(score.ratio, 1.0);
    });

    test('a relation with unreadable endpoints is excluded, not failed', () {
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [
          rel('Customer', 'Order', 'place'),
          rel('', '?', 'ghost'),
        ],
        document: docOf(['A Customer can place an Order.']),
      );
      expect(score.unreadableCount, 1);
      expect(
        score.total,
        1.0,
        reason: 'the ghost must not reach the denominator',
      );
      expect(score.ratio, 1.0);
    });

    test('nothing audited => null ratio, NEVER a perfect 0/0', () {
      // The trap: 0/0 naive-divides to NaN or rounds to 1.0, and a report would
      // claim "100% consistent" about a diagram nobody read.
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: const [],
        document: docOf(['A Customer can place an Order.']),
      );
      expect(score.ratio, isNull);
    });
  });

  group('toFinding — honest, and not scored', () {
    test('below threshold names what did not match', () {
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [rel('A', 'B', 'alpha'), rel('B', 'C', 'beta')],
        document: docOf(['alpha only']),
      );
      final finding = score.toFinding(
        subject: 'chain2',
        english: 'ERD 50%. No match: ${score.unmatched.join('; ')}.',
        vietnamese: 'ERD 50%. Không khớp: ${score.unmatched.join('; ')}.',
      );
      expect(finding.check, CheckId.fkMatrixMismatch);
      expect(finding.passed, isFalse);
      expect(finding.messageEn, contains('beta'));
      expect(finding.actual, closeTo(0.5, 1e-9));
    });

    test('the row is PENDING-VISION until an audit resolves it', () {
      // A ratio built from a vision read cannot be re-derived from text, so it
      // must not seed the ledger as a plain open row.
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [rel('A', 'B', 'alpha')],
        document: docOf(['alpha']),
      );
      final finding = score.toFinding(
        subject: 'chain2',
        english: 'ok',
        vietnamese: 'ok',
      );
      expect(finding.requiresVisionEvidence, isTrue);
      expect(finding.passed, isTrue);
    });
  });

  group('wire contract — the three places must not drift (AC7)', () {
    test('fk_matrix_mismatch is the wire id', () {
      expect(CheckId.fkMatrixMismatch.wire, 'fk_matrix_mismatch');
    });

    test('the finding round-trips through JSON', () {
      // Sessions are persisted; a new check that cannot re-read its own row
      // would make a saved report unopenable.
      final score = CrossArtifactChecker.scoreFkMatrix(
        relationships: [rel('A', 'B', 'alpha')],
        document: docOf(['alpha']),
      );
      final finding = score.toFinding(
        subject: 'chain2',
        english: 'ERD matches',
        vietnamese: 'ERD khớp',
      );
      final back = DeterministicFinding.fromJson(finding.toJson());
      expect(back.check, CheckId.fkMatrixMismatch);
      expect(back.messageEn, finding.messageEn);
      expect(back.actual, finding.actual);
    });
  });
}
