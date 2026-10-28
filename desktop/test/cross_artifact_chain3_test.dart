/// Chain 3 (Sequence ↔ Class) — the five counting rules of `scoring.md:113`.
///
/// These five rules exist because two competent reviewers scored the SAME
/// document 0.56 and 0.70 (rulebook 1.6, ambiguity A3). Every rule below is a
/// decision somebody had to make after that disagreement, so each has a test
/// with a hand-computed number. A rule without a test is a rule that quietly
/// changes next time somebody tidies this file.
///
/// Three numbers here are NOT the naive reading, and all three surprised the
/// author while writing it. They are pinned on purpose:
///
///   * the half-sum is weighted by ITEM COUNT, so "1 of 2 lifelines bad, 0 of 1
///     messages bad" is 1/3 — not the 0.5 of a plain item ratio, and not the
///     0.25 of a naive mean of the two halves;
///   * operations are compared WITHOUT stemming, because `stemOf` strips a
///     trailing "s" and would make `to_citation` match `to_citations` — the
///     exact difference rule 2 exists to catch;
///   * a class-side name is accepted with OR without its file extension, on
///     purpose, so the rule-3 suffix test below is about the LIFELINE side.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/diagram_audit/services/cross_artifact_checker.dart';

ChainScore score(
  SequenceInventory seq, {
  Set<String> classes = const {},
  Set<String> ops = const {},
}) => CrossArtifactChecker.scoreSequenceVsClass(
  sequence: seq,
  classNames: classes,
  operations: ops,
);

void main() {
  group('the weighted half-sum (scoring.md:113)', () {
    test('a perfect figure scores 1.0', () {
      // By hand: 2 good lifelines + 2 good messages = 2 points earned, over
      // (2 + 2) / 2 = 2 possible => 1.0
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller', 'UserService'],
          messages: ['login', 'logout'],
        ),
        classes: {'Controller', 'UserService'},
        ops: {'login', 'logout'},
      );
      expect(s.ratio, 1.0);
    });

    test('1 of 2 lifelines bad and 0 of 1 messages bad is 1/3', () {
      // By hand: 1 good lifeline + 0 good messages = 0.5 earned, over
      // (2 + 1) / 2 = 1.5 possible => 1/3. NOT 0.5 (plain item ratio) and NOT
      // 0.25 (naive mean of halves) — scoring.md:113 weights by item count.
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller', 'Database'],
          messages: ['login'],
        ),
        classes: {'Controller'},
        ops: const {},
      );
      expect(s.ratio, closeTo(1 / 3, 1e-9));
    });

    test('a figure with no messages is judged on its lifelines alone', () {
      // Measured: 2 lifelines resolve, 0 messages => 1 point over 1 possible.
      // No message arrows is not a defect and must not halve the figure.
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller', 'UserService'],
          messages: [],
        ),
        classes: {'Controller', 'UserService'},
      );
      expect(s.ratio, 1.0);
    });

    test('an unreadable or empty figure is unmeasured — not 0, not 1', () {
      expect(
        score(const SequenceInventory(lifelines: [], messages: [])).ratio,
        isNull,
      );
      expect(
        score(
          const SequenceInventory(
            lifelines: ['Controller'],
            messages: ['handle'],
            unreadable: true,
          ),
          classes: {'Controller'},
          ops: {'handle'},
        ).ratio,
        isNull,
      );
    });
  });

  group('rule 1 — call messages only', () {
    test('a reply arrow never reaches the count', () {
      // The vision pass excludes replies upstream; this pins the contract so a
      // caller that forgets cannot quietly halve the ratio.
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller'],
          messages: ['handle'],
        ),
        classes: {'Controller'},
        ops: {'handle'},
      );
      expect(s.ratio, 1.0);
    });
  });

  group('rule 2 — exact name match, case-sensitive, NO stemming', () {
    test('a trailing s is NOT forgiven: this is the finding', () {
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller'],
          messages: ['to_citation'],
        ),
        classes: {'Controller'},
        ops: {'to_citations'},
      );
      // By hand: 1 good lifeline + 0 good messages = 0.5 over (1+1)/2 = 1 => 0.5
      expect(s.ratio, closeTo(0.5, 1e-9));
      expect(s.unmatched, contains('to_citation'));
    });

    test('a lifeline with no declared class IS a finding', () {
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller', 'Database'],
          messages: [],
        ),
        classes: {'Controller'},
      );
      expect(s.unmatched, contains('Database'));
    });
  });

  group('rule 3 — only two normalisations, both opt-in', () {
    test('a shared file suffix is stripped when EVERY lifeline carries it', () {
      // 'chat_routes.py' with the '.py' removed matches the class
      // 'chat_routes': the author's convention, not naming drift.
      final s = score(
        const SequenceInventory(
          lifelines: ['chat_routes.py', 'rag.py'],
          messages: ['ingest'],
        ),
        classes: {'chat_routes', 'rag'},
        ops: {'ingest'},
      );
      expect(s.ratio, 1.0);
    });

    test('a receiver prefix is always stripped from a message', () {
      final s = score(
        const SequenceInventory(
          lifelines: ['Client'],
          messages: ['ragClientService.ingest(x)'],
        ),
        classes: {'Client'},
        ops: {'ingest'},
      );
      expect(s.ratio, 1.0);
    });

    test('a class name is accepted with or without its extension', () {
      // Deliberate one-sided leniency, and pinned so it cannot drift into a
      // blanket allow: a class diagram may write `chat_routes.py` in one box
      // and `chat_routes` in another. The chain reports a lifeline with NO
      // class, not a disagreement about where a dot goes.
      expect(classStemOf('chat_routes.py'), classStemOf('chat_routes'));
    });
  });

  group('rule 4 — a missing class fails its lifeline AND its messages', () {
    test('one absent class is counted twice', () {
      final s = score(
        const SequenceInventory(
          lifelines: ['Controller', 'Database'],
          messages: ['query'],
        ),
        classes: {'Controller'},
        ops: const {},
      );
      expect(s.unmatched, containsAll(<String>['Database', 'query']));
      // By hand: 1 good lifeline + 0 good messages = 0.5 over 1.5 => 1/3
      expect(s.ratio, closeTo(1 / 3, 1e-9));
    });
  });
}
