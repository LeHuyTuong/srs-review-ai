/// Round 8 wire contract — the goal-§3 ledger has five states
/// (open/fixed/verified/pending-vision/disputed). Two invariants must
/// hold for every snapshot to round-trip:
///
///   1. the new wire names round-trip through FindingStatus.fromName;
///   2. the legacy aliases `accepted`/`dismissed` written by Round ≤7
///      still resolve to the new model (fixed / disputed) so a Round 5
///      workspace opened in Round 8 keeps the meaning of every status
///      a user ever set.
///
/// Reading from a never-seen name must always degrade to `open` —
/// never throw — because future enum values may show up in older
/// snapshots.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';

void main() {
  group('FindingStatus — five-state ledger (goal §3)', () {
    test('enum exposes exactly the five states in canonical order', () {
      // Order is a contract too: the filter dropdown renders values in
      // declaration order, and the dashboard "fixed vs pending vs
      // disputed" columns count on a stable sequence.
      expect(FindingStatus.values.map((s) => s.name).toList(growable: false), [
        'open',
        'fixed',
        'verified',
        'pendingVision',
        'disputed',
      ]);
    });

    test('every value has a non-empty, human-facing label', () {
      // Goal §3 calls the values by their full word; the label is what
      // users actually see. None may be empty or share a label.
      final labels = FindingStatus.values.map((s) => s.label).toList();
      expect(
        labels.toSet().length,
        labels.length,
        reason: 'labels must be unique',
      );
      expect(labels.every((l) => l.isNotEmpty), isTrue);
    });

    test('fromName round-trips every new wire name', () {
      // The snapshot serialiser writes `status.name`; the restore side
      // must read it back identically. One assertion per value so a
      // future rename of one value cannot hide.
      expect(FindingStatus.fromName('open'), FindingStatus.open);
      expect(FindingStatus.fromName('fixed'), FindingStatus.fixed);
      expect(FindingStatus.fromName('verified'), FindingStatus.verified);
      expect(
        FindingStatus.fromName('pendingVision'),
        FindingStatus.pendingVision,
      );
      expect(FindingStatus.fromName('disputed'), FindingStatus.disputed);
    });

    test('legacy aliases accepted/dismissed still resolve', () {
      // A Round ≤7 workspace on disk has FindingStatus.accepted /
      // .dismissed in its JSON. Round 8 renamed those to .fixed /
      // .disputed. The deserialiser maps the legacy names forward so
      // every status a student ever set keeps its meaning — open
      // stays open, accepted becomes fixed, dismissed becomes
      // disputed. Verified and pending-vision did not exist in ≤7
      // and have no alias to preserve.
      expect(FindingStatus.fromName('accepted'), FindingStatus.fixed);
      expect(FindingStatus.fromName('dismissed'), FindingStatus.disputed);
    });

    test('unknown / null names degrade to open, never throw', () {
      // Two cases: a value the code never knew (typo, future enum
      // value appearing in older snapshots) and null (the snapshot
      // was written before triage existed). Both must read as open —
      // the safest fallback — without raising, because a session that
      // refuses to open is worse than one that opens with an open
      // status.
      expect(FindingStatus.fromName(null), FindingStatus.open);
      expect(FindingStatus.fromName(''), FindingStatus.open);
      expect(FindingStatus.fromName('fixed-but-with-typo'), FindingStatus.open);
      expect(FindingStatus.fromName('SUPERSEEDED'), FindingStatus.open);
    });
  });
}
