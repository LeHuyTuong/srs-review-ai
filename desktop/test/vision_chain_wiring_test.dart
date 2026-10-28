/// Plan 10, phase A — does the SERVICE wire chains 2 and 3 correctly?
///
/// `cross_artifact_chain3_test.dart` proves the scoring FUNCTION. Nothing
/// proved the WIRING, and the wiring is where this chain can lie to the user.
/// Two real defects were found here on the first measurement, both the same
/// shape — the chain praising a document it never cross-checked:
///
///  1. Sequence and class share the SAME ledger family `SEQ-CLS`
///     (diagram_type_classifier.dart:28-29), so the branch keyed on that label
///     put every page's elements into BOTH sides of chain 3. A sequence figure
///     was compared with its own lifelines: ratio 1.0, always.
///  2. `declaredOperations` was filled from EVERY audited page, so a sequence
///     message counted as the class operation it was supposed to be checked
///     against — rule 3 of scoring.md:119 passed by construction.
///
/// Every case asserts a row proving the page WAS audited before concluding
/// "no chain row". Asserting absence on a run that never happened is not
/// evidence: the first draft of this file did exactly that and went green
/// three ways while measuring nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/diagram_audit/models/diagram_audit.dart';
import 'package:srs_review_ai/diagram_audit/services/vision_review_service.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';

/// Tier-1 phrases from the classifier's own evidence table, so each page is
/// named for the kind we mean and a tie cannot demote it to unknown.
const _classText = 'Figure 1. Class diagram of the course module.';
const _sequenceText = 'Figure 2. Sequence diagram for lecturer login.';
const _erdText = 'Figure 3. Entity relationship diagram of the schema.';
const _activityText = 'Figure 4. Activity diagram for mute action.';

SrsDocument _doc(List<String> pageTexts) => SrsDocument(
  fileName: 'a.pdf',
  pageCount: pageTexts.length,
  pageTexts: pageTexts,
  requirements: const [],
  imagePageIndexes: [for (var i = 0; i < pageTexts.length; i++) i],
);

DiagramAuditResult _result({
  required int page,
  required String type,
  List<String> elements = const [],
  List<String> operations = const [],
  List<String> unreadable = const [],
}) => DiagramAuditResult(
  pageIndex: page,
  diagramType: type,
  elements: elements,
  relations: [
    for (final op in operations)
      DiagramRelationData(
        source: elements.isEmpty ? 'x' : elements.first,
        target: elements.length > 1 ? elements[1] : 'y',
        label: op,
        arrowheadSide: 'unknown',
      ),
  ],
  unreadable: unreadable,
  clean: true,
  findings: const [],
  model: 'fake',
  cached: false,
  mock: true,
);

/// Replays one scripted result per page index; anything else is a blank page.
VisionReviewService _svc(Map<int, DiagramAuditResult> script) =>
    VisionReviewService(
      auditor: (req) async =>
          script[req.pageIndex] ??
          DiagramAuditResult(
            pageIndex: req.pageIndex,
            diagramType: req.diagramType,
            elements: const [],
            relations: const [],
            unreadable: const [],
            clean: true,
            findings: const [],
            model: 'fake',
            cached: false,
            mock: true,
          ),
      renderPage: (_, _) async => 'img',
      maxPages: 10,
    );

/// Class page: Controller/UserService, declaring `register`.
DiagramAuditResult _classPage(int page) => _result(
  page: page,
  type: 'class',
  elements: ['Controller', 'UserService'],
  operations: ['register'],
);

/// Sequence page: the same two lifelines, but it CALLS `login`, which no class
/// diagram ever declared.
DiagramAuditResult _sequencePage(
  int page, {
  List<String> unreadable = const [],
}) => _result(
  page: page,
  type: 'sequence',
  elements: ['Controller', 'UserService'],
  operations: ['login'],
  unreadable: unreadable,
);

List<String> _subjects(VisionAuditOutcome outcome) => [
  for (final f in outcome.findings) f.subject ?? '',
];

/// The `actual` of every row filed under [subject]. A chain row must always
/// carry a number: a null here would mean a ratio was reported without a
/// measurement, so the cases that expect a value assert on it directly.
List<num?> _chainActuals(VisionAuditOutcome outcome, String subject) => [
  for (final f in outcome.findings)
    if (f.subject == subject) f.actual,
];

void main() {
  group('chain 3 wiring', () {
    // Both kinds live in the `SEQ-CLS` family, so two audited pages of these
    // kinds are named SEQ-CLS-01 and SEQ-CLS-02 — the subject cannot tell the
    // reader which is which, which is itself worth knowing.
    test('A1 — class page AND sequence page yield one chain3 row', () async {
      final outcome = await _svc({
        0: _classPage(0),
        1: _sequencePage(1),
      }).audit(_doc([_classText, _sequenceText]));
      expect(
        _subjects(outcome),
        containsAll(<String>['SEQ-CLS-01', 'SEQ-CLS-02']),
      );
      final actuals = _chainActuals(outcome, 'chain3-sequence');
      expect(actuals, hasLength(1));
      // Lifelines resolve 2/2 and `login` is declared on nothing (0/1). The
      // formula is the item-weighted half-sum, NOT an average of the halves:
      // (2/2) / (3/2) = 2/3. Expecting 0.5 here is the flat-average mistake
      // that scoring.md:119 exists to prevent — see cross_artifact_chain3_test.
      expect(actuals.single, closeTo(2 / 3, 0.001));
    });

    test('A2 — class page alone yields NO chain3 row', () async {
      final outcome = await _svc({0: _classPage(0)}).audit(_doc([_classText]));
      expect(_subjects(outcome), contains('SEQ-CLS-01'));
      expect(
        _chainActuals(outcome, 'chain3-sequence'),
        isEmpty,
        reason:
            'one half of the comparison is missing; nothing may be reported',
      );
    });

    test(
      'A3 — a sequence page alone must not be compared with itself',
      () async {
        // Regression for defect 1: before the fix this reported 1.0, because the
        // figure's own lifelines also filled the class side.
        final outcome = await _svc({
          0: _sequencePage(0),
        }).audit(_doc([_sequenceText]));
        expect(_subjects(outcome), contains('SEQ-CLS-01'));
        expect(
          _chainActuals(outcome, 'chain3-sequence'),
          isEmpty,
          reason:
              'a figure compared with itself always agrees and proves nothing',
        );
      },
    );

    test('A4 — an unreadable sequence page yields no row, not a zero', () async {
      // scoring.md rule 4: a page the model refused to guess at is MISSING
      // evidence, not a defect. Scoring it 0 would put red on a diagram nobody
      // could read.
      final outcome = await _svc({
        0: _classPage(0),
        1: _sequencePage(1, unreadable: const ['labels too small to read']),
      }).audit(_doc([_classText, _sequenceText]));
      expect(
        _subjects(outcome),
        containsAll(<String>['SEQ-CLS-01', 'SEQ-CLS-02']),
      );
      expect(
        _chainActuals(outcome, 'chain3-sequence'),
        isEmpty,
        reason: 'unreadable must degrade to unmeasured, never to a failure',
      );
    });

    test('A5 — an ERD page must not supply the class side of chain 3', () async {
      // The ERD entities carry the SAME names as the lifelines. If they fed the
      // class side, the chain would report an agreement no class diagram ever
      // asserted — and an SDS holding only an ERD plus a sequence figure would
      // take full marks on a chain it never drew.
      final outcome = await _svc({
        0: _result(
          page: 0,
          type: 'erd',
          elements: ['Controller', 'UserService'],
          operations: ['login'],
        ),
        1: _sequencePage(1),
      }).audit(_doc([_erdText, _sequenceText]));
      expect(_subjects(outcome), containsAll(<String>['ERD-01', 'SEQ-CLS-01']));
      expect(
        _chainActuals(outcome, 'chain3-sequence'),
        isEmpty,
        reason: 'an ERD is not a class diagram',
      );
    });

    test('A6 — a sequence message is not its own declared operation', () async {
      // Regression for defect 2: `declaredOperations` used to be filled from
      // every page, so `login` arrived from the sequence figure and satisfied
      // the very rule meant to test it. 1.0 here means that rule went vacuous
      // again.
      final outcome = await _svc({
        0: _classPage(0),
        1: _sequencePage(1),
      }).audit(_doc([_classText, _sequenceText]));
      final actuals = _chainActuals(outcome, 'chain3-sequence');
      expect(actuals, hasLength(1));
      expect(
        actuals.single,
        lessThan(1.0),
        reason:
            'login was never declared on a class diagram; a perfect score '
            'means the sequence figure supplied its own evidence',
      );
    });
  });

  group('chain 2 wiring', () {
    test('ERD relationships reach the chain2 row', () async {
      final outcome = await _svc({
        0: _result(
          page: 0,
          type: 'erd',
          elements: ['Controller', 'UserService'],
          operations: ['own'],
        ),
      }).audit(_doc([_erdText]));
      expect(_subjects(outcome), contains('ERD-01'));
      // 'own' appears in no requirement text, so the honest reading is 0%.
      expect(_chainActuals(outcome, 'chain2-erd'), <num?>[0.0]);
    });

    test('an unreadable ERD page yields no chain2 row', () async {
      final outcome = await _svc({
        0: _result(
          page: 0,
          type: 'erd',
          elements: ['Controller'],
          operations: ['own'],
          unreadable: const ['too small'],
        ),
      }).audit(_doc([_erdText]));
      expect(_subjects(outcome), contains('ERD-01'));
      expect(
        _chainActuals(outcome, 'chain2-erd'),
        isEmpty,
        reason: 'scoring.md:125 — an unread page is excluded from both counts',
      );
    });

    test('an activity page contributes to neither chain', () async {
      final outcome = await _svc({
        0: _result(
          page: 0,
          type: 'activity',
          elements: ['mute action', 'decision node'],
          operations: ['mute'],
        ),
      }).audit(_doc([_activityText]));
      expect(_subjects(outcome), contains('ACT-01'));
      expect(_chainActuals(outcome, 'chain2-erd'), isEmpty);
      expect(_chainActuals(outcome, 'chain3-sequence'), isEmpty);
    });
  });
}
