/// Round 10 — wire-contract tests for the two surfaces the "Re-verify"
/// button and the degraded-mode chip depend on:
///
///   - [WorkspaceState.currentMode]: derived run mode from the same
///     inputs the report uses. Goal §0 demands this be honest —
///     "scanned PDF" must say "blind", "no diagrams" must say
///     "text-first", never the other way around.
///   - [VerifyDiff.compute]: counts transitions for the deterministic
///     subset only. AI finding ids never contribute, mirroring the
///     Verifier's own scope rule.
///
/// No I/O, no Riverpod, no parser — these are pure Dart unit tests so
/// the regression surface stays tight.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';

void main() {
  // ---------------------------------------------------------------- currentMode

  group('currentMode — goal §0 degraded-mode-first', () {
    test('scanned PDF (units empty, vision ready) → blind', () {
      // The parser produced zero units but kept the PDF bytes (vision
      // is still reachable). The run cannot pretend it has text.
      expect(
        ReviewMode.decide(
          unitsEmpty: true,
          visionReady: true,
          hasDiagrams: false,
        ),
        ReviewMode.blind,
      );
    });

    test('text + diagrams + vision → full', () {
      expect(
        ReviewMode.decide(
          unitsEmpty: false,
          visionReady: true,
          hasDiagrams: true,
        ),
        ReviewMode.full,
      );
    });

    test('text + no diagrams + vision → text-first', () {
      // Diagrams existed but were never flagged — vision pass is
      // reachable but has nothing to look at.
      expect(
        ReviewMode.decide(
          unitsEmpty: false,
          visionReady: true,
          hasDiagrams: false,
        ),
        ReviewMode.textFirst,
      );
    });

    test('text but no vision → text-first (DOCX import)', () {
      expect(
        ReviewMode.decide(
          unitsEmpty: false,
          visionReady: false,
          hasDiagrams: false,
        ),
        ReviewMode.textFirst,
      );
    });

    test('text + diagrams but no vision → text-first', () {
      // DOCX diagrams in prose only — vision never applies.
      expect(
        ReviewMode.decide(
          unitsEmpty: false,
          visionReady: false,
          hasDiagrams: true,
        ),
        ReviewMode.textFirst,
      );
    });

    test('empty document with no vision → text-first', () {
      // An empty DOCX or a DOCX with no extracted text and no PDF
      // bytes is not "blind" (no PDF was loaded); it is text-first
      // because no vision path was even attempted.
      expect(
        ReviewMode.decide(
          unitsEmpty: true,
          visionReady: false,
          hasDiagrams: false,
        ),
        ReviewMode.textFirst,
      );
    });

    test('ReviewMode.label is non-empty for every value', () {
      // Goal §0 demands the chip declare what the run covers. Empty
      // label = silent = fake coverage.
      for (final mode in ReviewMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });
  });

  // ----------------------------------------------------------------- VerifyDiff

  group('VerifyDiff.compute — counts only deterministic transitions', () {
    test('a single promotion is counted', () {
      final diff = VerifyDiff.compute(
        before: {'language:UC-01': FindingStatus.fixed},
        after: {'language:UC-01': FindingStatus.verified},
      );
      expect(diff.promotedToVerified, 1);
      expect(diff.reopened, 0);
      expect(diff.unchanged, 0);
    });

    test('a single regression is counted as reopened', () {
      final diff = VerifyDiff.compute(
        before: {'language:UC-01': FindingStatus.verified},
        after: {'language:UC-01': FindingStatus.open},
      );
      expect(diff.promotedToVerified, 0);
      expect(diff.reopened, 1);
      expect(diff.unchanged, 0);
    });

    test('no-op diff is empty', () {
      const diff = VerifyDiff.empty();
      expect(diff.isEmpty, isTrue);
      expect(diff.summary, '0 unchanged');
    });

    test('mixed: 2 promoted, 1 reopened, 3 unchanged', () {
      // Six deterministic ids: 2 fixed→verified, 1 verified→open
      // (regression), 3 stayed the same (2 open→open, 1 fixed→fixed).
      final diff = VerifyDiff.compute(
        before: {
          'language:UC-01': FindingStatus.fixed,
          'language:UC-02': FindingStatus.fixed,
          'language:UC-03': FindingStatus.verified,
          'language:UC-04': FindingStatus.open,
          'language:UC-05': FindingStatus.open,
          'uc_size:UC-06': FindingStatus.fixed,
        },
        after: {
          'language:UC-01': FindingStatus.verified,
          'language:UC-02': FindingStatus.verified,
          'language:UC-03': FindingStatus.open,
          'language:UC-04': FindingStatus.open,
          'language:UC-05': FindingStatus.open,
          'uc_size:UC-06': FindingStatus.fixed,
        },
      );
      expect(diff.promotedToVerified, 2);
      expect(diff.reopened, 1);
      expect(diff.unchanged, 3);
      expect(diff.summary, '2 promoted to verified · 1 reopened · 3 unchanged');
    });

    test('AI finding ids do not contribute to the diff', () {
      // Even when the AI id transitions, the diff ignores it — the
      // deterministic re-run is not evidence to re-classify an AI
      // verdict.
      final diff = VerifyDiff.compute(
        before: {
          'SEQ-CLS-01': FindingStatus.open,
          'language:UC-01': FindingStatus.fixed,
        },
        after: {
          'SEQ-CLS-01': FindingStatus.verified,
          'language:UC-01': FindingStatus.verified,
        },
      );
      expect(diff.promotedToVerified, 1);
      expect(diff.reopened, 0);
      expect(diff.unchanged, 0);
    });

    test('summary omits zero counters', () {
      // "0 promoted" or "0 reopened" clutter the snack bar — only the
      // non-zero numbers land in the message.
      final diff = VerifyDiff.compute(
        before: {'language:UC-01': FindingStatus.open},
        after: {'language:UC-01': FindingStatus.verified},
      );
      expect(diff.summary, '1 promoted to verified · 0 unchanged');
    });
  });
}
