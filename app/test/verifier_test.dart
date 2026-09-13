/// Round 9 — Verifier behaviour tests.
///
/// Goal §3 invariants encoded as tests so a regression to "auto-promote
/// without evidence" or "auto-promote disputed" fails CI on the next
/// change, not when a user opens a saved workspace three weeks later.
///
/// Each test pairs a tiny set of fresh findings with a tiny set of
/// previous statuses and asserts the resulting map. No I/O, no parser.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/verifier.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';

const _verifier = Verifier();

DeterministicFinding _uc(String id, {required bool passed}) =>
    DeterministicFinding(
      check: CheckId.language,
      passed: passed,
      severity: passed ? Severity.low : Severity.high,
      message: 'UC $id is not written in English.',
      subject: id,
    );

DeterministicFinding _missingPostcondition(String id, {required bool passed}) =>
    DeterministicFinding(
      check: CheckId.missingPostcondition,
      passed: passed,
      severity: passed ? Severity.low : Severity.high,
      message: 'UC $id has no Postcondition section.',
      subject: id,
    );

void main() {
  group('Verifier — goal §3 invariant 2 (verified needs evidence)', () {
    test('fixed + check now passes → verified', () {
      // The user marked UC-01 fixed; the re-run no longer flags it as
      // non-English. That is the evidence rule 2 requires.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.fixed},
        syllabusFindings: [_uc('UC-01', passed: true)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.verified);
    });

    test('fixed + check still fails → open (the fix did not hold)', () {
      // The user marked UC-01 fixed but the re-run still flags it. The
      // status must drop back to open, otherwise the dashboard would
      // celebrate a fix that never happened.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.fixed},
        syllabusFindings: [_uc('UC-01', passed: false)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.open);
    });

    test('verified + regression → open', () {
      // The verifier put UC-01 in verified last round; this round it
      // fails again. The verifier promoted without a human, the next
      // run contradicts, so the row reopens.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.verified},
        syllabusFindings: [_uc('UC-01', passed: false)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.open);
    });
  });

  group('Verifier — silent fix (open + not failing → verified)', () {
    test('open + check no longer fires → verified', () {
      // The user never marked anything; the document was just edited
      // outside the app and the check no longer fires. Rule 2 says
      // evidence is enough — a passing run IS evidence. Promote.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.open},
        syllabusFindings: [_uc('UC-01', passed: true)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.verified);
    });
  });

  group('Verifier — goal §3 invariant 3 (disputed stays disputed)', () {
    test('disputed + check still fails → disputed (no auto-promote)', () {
      // The user marked UC-01 as a false positive. The next run still
      // fires, but rule 3 says a contested row must not be promoted
      // without the user re-touching it. Stays disputed.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.disputed},
        syllabusFindings: [_uc('UC-01', passed: false)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.disputed);
    });

    test('disputed + check passes → disputed (do not silently close)', () {
      // Even if the check now passes, the user's dispute stands until
      // they re-open the row. Otherwise a contested finding could
      // disappear from the report without the user knowing.
      final next = _verifier.verify(
        previousStatuses: {'language:UC-01': FindingStatus.disputed},
        syllabusFindings: [_uc('UC-01', passed: true)],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.disputed);
    });
  });

  group('Verifier — goal §3 invariant 3 (pendingVision is a one-way)', () {
    test(
      'pendingVision + check now passes → verified (the goal is reachable)',
      () {
        // A vision-only goal becomes verifiable in the text path. The
        // row graduates to verified rather than staying pending.
        final next = _verifier.verify(
          previousStatuses: {
            'missing_postcondition:UC-01': FindingStatus.pendingVision,
          },
          syllabusFindings: const [],
          referenceFindings: [
            _missingPostcondition('UC-01', passed: true),
          ],
        );
        expect(
          next['missing_postcondition:UC-01'],
          FindingStatus.verified,
        );
      },
    );

    test('pendingVision + still failing → pendingVision', () {
      final next = _verifier.verify(
        previousStatuses: {
          'missing_postcondition:UC-01': FindingStatus.pendingVision,
        },
        syllabusFindings: const [],
        referenceFindings: [
          _missingPostcondition('UC-01', passed: false),
        ],
      );
      expect(
        next['missing_postcondition:UC-01'],
        FindingStatus.pendingVision,
      );
    });
  });

  group('Verifier — id stability (rule 1)', () {
    test('every previous id is preserved in the output, even when fixed', () {
      // Rule 1: ids never disappear. UC-01 (open) → verified because
      // the new check no longer fires. UC-02 (fixed) → verified.
      // UC-03 (disputed) stays disputed (rule 3).
      final next = _verifier.verify(
        previousStatuses: {
          'language:UC-01': FindingStatus.open,
          'language:UC-02': FindingStatus.fixed,
          'language:UC-03': FindingStatus.disputed,
        },
        syllabusFindings: [
          _uc('UC-01', passed: true),
          _uc('UC-02', passed: true),
          _uc('UC-03', passed: false),
        ],
        referenceFindings: const [],
      );
      expect(next['language:UC-01'], FindingStatus.verified);
      expect(next['language:UC-02'], FindingStatus.verified);
      expect(next['language:UC-03'], FindingStatus.disputed);
      // And no row from the previous map has been dropped.
      expect(
        next.keys.toSet(),
        {'language:UC-01', 'language:UC-02', 'language:UC-03'},
      );
    });

    test('a fresh failure introduces its own key as open', () {
      // UC-99 has never been seen before; the verifier opens it.
      final next = _verifier.verify(
        previousStatuses: const {},
        syllabusFindings: [_uc('UC-99', passed: false)],
        referenceFindings: const [],
      );
      expect(next['language:UC-99'], FindingStatus.open);
    });
  });

  group('Verifier — mixed families in one run', () {
    test('syllabus + reference findings share the status keying', () {
      // A syllabus finding and a reference finding for the same UC id
      // are two distinct ledger rows (different check.wire prefix) —
      // they must not collide, so the user can see both under UC-01.
      final next = _verifier.verify(
        previousStatuses: {
          'language:UC-01': FindingStatus.open,
          'missing_postcondition:UC-01': FindingStatus.fixed,
        },
        syllabusFindings: [_uc('UC-01', passed: false)],
        referenceFindings: [
          _missingPostcondition('UC-01', passed: true),
        ],
      );
      expect(next['language:UC-01'], FindingStatus.open);
      expect(
        next['missing_postcondition:UC-01'],
        FindingStatus.verified,
      );
    });
  });

  group('Verifier — AI finding ids pass through untouched', () {
    test('AI status survives even when the deterministic set is empty', () {
      // The same map will eventually carry AI ids (`SEQ-CLS-01`) and
      // deterministic keys side by side. A deterministic re-run must
      // never auto-promote an AI verdict — the system did not produce
      // the evidence to do that. This test pins that boundary.
      final next = _verifier.verify(
        previousStatuses: {
          'SEQ-CLS-01': FindingStatus.open,
          'TRACE-01': FindingStatus.disputed,
          'language:UC-01': FindingStatus.fixed,
        },
        syllabusFindings: [_uc('UC-01', passed: true)],
        referenceFindings: const [],
      );
      expect(next['SEQ-CLS-01'], FindingStatus.open);
      expect(next['TRACE-01'], FindingStatus.disputed);
      expect(next['language:UC-01'], FindingStatus.verified);
    });
  });

  // --------------------------------------------------- R26 — UNV upstream
  // signal: a finding whose DeterministicFinding.requiresVisionEvidence is
  // true must be seeded as pendingVision, not open. The brief says vision-
  // required findings must NEVER be tinted green, so they begin in limbo
  // and the Verifier's transition table can only promote them when the
  // text-only path confirms the check no longer fires.
  group('Verifier — UNV upstream signal (pendingVision seeded for vision-required findings)', () {
    test(
      'fresh finding with requiresVisionEvidence → initial status is pendingVision, not open',
      () {
        final next = _verifier.verify(
          previousStatuses: const {},
          syllabusFindings: const [],
          referenceFindings: const [
            DeterministicFinding(
              check: CheckId.crossArtifactName,
              passed: false,
              severity: Severity.high,
              subject: 'UC-01',
              message: 'diagram-vs-text inconsistency',
              requiresVisionEvidence: true,
            ),
          ],
        );
        expect(next['cross_artifact_name:UC-01'],
            FindingStatus.pendingVision);
      },
    );

    test(
      'fresh finding WITHOUT requiresVisionEvidence → initial status stays open',
      () {
        final next = _verifier.verify(
          previousStatuses: const {},
          syllabusFindings: const [],
          referenceFindings: const [
            DeterministicFinding(
              check: CheckId.duplicateIds,
              passed: false,
              severity: Severity.high,
              subject: 'UC04',
              message: 'id reused',
            ),
          ],
        );
        expect(next['duplicate_ids:UC04'], FindingStatus.open);
      },
    );

    test(
      'pendingVision + check no longer fires → verified (text-only path confirms)',
      () {
        final next = _verifier.verify(
          previousStatuses: const {
            'cross_artifact_name:UC-01': FindingStatus.pendingVision,
          },
          syllabusFindings: const [],
          referenceFindings: const [],
        );
        expect(next['cross_artifact_name:UC-01'],
            FindingStatus.verified);
      },
    );

    test(
      'pendingVision + check still fails → pendingVision (never auto-promotes)',
      () {
        final next = _verifier.verify(
          previousStatuses: const {
            'cross_artifact_name:UC-01': FindingStatus.pendingVision,
          },
          syllabusFindings: const [],
          referenceFindings: const [
            DeterministicFinding(
              check: CheckId.crossArtifactName,
              passed: false,
              severity: Severity.high,
              subject: 'UC-01',
              message: 'still inconsistent',
              requiresVisionEvidence: true,
            ),
          ],
        );
        expect(next['cross_artifact_name:UC-01'],
            FindingStatus.pendingVision);
      },
    );
  });
}