import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/reference_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';

/// `SrsDocument` is built by the parser; for unit tests we reach the private
/// constructor and assemble inputs by hand so each test names exactly what it
/// is exercising. The splitter has its own integration coverage; these tests
/// guarantee the *checks* do what the name says on the data the splitter
/// hands them.
SrsDocument _doc(List<RequirementItem> items) => SrsDocument(
  fileName: 'fixture.docx',
  pageCount: 1,
  pageTexts: const [''],
  requirements: items,
);

RequirementItem _useCase(String id, String text) => RequirementItem(
  id: id,
  text: text,
  kind: RequirementKind.useCase,
  section: '3.2',
  pageIndex: 0,
);

RequirementItem _fr(String id, String text) => RequirementItem(
  id: id,
  text: text,
  kind: RequirementKind.functional,
  section: '3.2',
  pageIndex: 0,
);

RequirementItem _statement(String text) => RequirementItem(
  id: 'STMT-1',
  text: text,
  kind: RequirementKind.statement,
  section: '3.2',
  pageIndex: 0,
);

void main() {
  const checks = ReferenceChecks();

  group('wire-level metadata', () {
    test('CheckId.wire and CheckId.label cover the new entries', () {
      expect(CheckId.duplicateIds.wire, 'duplicate_ids');
      expect(CheckId.duplicateIds.label, 'Duplicate requirement ids');
      expect(CheckId.missingPostcondition.wire, 'missing_postcondition');
      expect(CheckId.missingPostcondition.label, 'Missing postcondition');
    });

    test('isReferenceCheck separates M2 from F7/F8/F9', () {
      expect(CheckId.ucCount.isReferenceCheck, isFalse);
      expect(CheckId.language.isReferenceCheck, isFalse);
      expect(CheckId.ucSize.isReferenceCheck, isFalse);
      expect(CheckId.duplicateIds.isReferenceCheck, isTrue);
      expect(CheckId.missingPostcondition.isReferenceCheck, isTrue);
    });

    test('fromJson round-trips the new wire values', () {
      final raw = {
        'check': 'duplicate_ids',
        'passed': false,
        'severity': 'high',
        'message': 'x',
        'subject': 'UC04',
        'actual': 7,
      };
      final parsed = DeterministicFinding.fromJson(raw);
      expect(parsed.check, CheckId.duplicateIds);
      expect(parsed.severity, Severity.high);
      expect(parsed.subject, 'UC04');
      expect(parsed.actual, 7);
    });
  });

  group('duplicateIds', () {
    test('empty document yields no findings', () {
      expect(checks.duplicateIds(_doc(const [])), isEmpty);
    });

    test('single occurrence per id is silent', () {
      final doc = _doc([
        _useCase('UC-01', 'Submit report. Postcondition: report saved.'),
        _useCase('UC-02', 'Cancel. Postcondition: form discarded.'),
        _fr('FR-03', 'The system shall export a PDF.'),
      ]);
      expect(checks.duplicateIds(doc), isEmpty);
    });

    test('OTES pattern: same UC id used by 7 rows → one high finding', () {
      // Faithfully models the OTES finding: UC04 labels 7 separate tables.
      final doc = _doc([
        for (var i = 0; i < 7; i++)
          _useCase('UC04', 'Use case table #${i + 1}.'),
        _fr('FR-08', 'Independent requirement.'),
      ]);
      final findings = checks.duplicateIds(doc);
      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.check, CheckId.duplicateIds);
      expect(finding.severity, Severity.high);
      expect(finding.passed, isFalse);
      expect(finding.subject, 'UC04');
      expect(finding.actual, 7);
      // The message must point at the count so the reader does not have to
      // recount by hand — a one-line summary that says "7 requirements".
      expect(finding.message, contains('7'));
    });

    test('multiple duplicate ids are reported, sorted by id', () {
      final doc = _doc([
        _useCase('UC-04', ''),
        _useCase('UC-04', ''),
        _useCase('UC-04', ''),
        _useCase('UC-09', ''),
        _useCase('UC-09', ''),
      ]);
      final findings = checks.duplicateIds(doc);
      expect(findings.map((f) => f.subject), ['UC-04', 'UC-09']);
      expect(findings.map((f) => f.actual), [3, 2]);
    });

    test('bare-modal statements are ignored even if reused', () {
      // Splitter synthesises an id for modal sentences, but reuse of those
      // synthetic ids is not the OTES-style signal we are after. Only
      // explicit-id items should appear.
      final doc = _doc([
        _statement('The system shall keep an audit log.'),
        _statement('The system shall keep an audit log.'),
        _statement('The system shall keep an audit log.'),
      ]);
      expect(checks.duplicateIds(doc), isEmpty);
    });
  });

  group('missingPostcondition', () {
    test('UC with Postcondition heading passes', () {
      final doc = _doc([
        _useCase('UC-01', '''
Submit weekly report
Main flow:
  1. User picks a date.
  2. App generates the PDF.
Postcondition: the PDF sits in the user's download folder.'''),
      ]);
      expect(checks.missingPostcondition(doc), isEmpty);
    });

    test('UC without Postcondition gets a high finding', () {
      final doc = _doc([
        _useCase(
          'UC-02',
          'Cancel a draft.\nMain flow:\n  1. User clicks Cancel.\n  2. App discards the form.',
        ),
      ]);
      final findings = checks.missingPostcondition(doc);
      expect(findings, hasLength(1));
      final f = findings.single;
      expect(f.check, CheckId.missingPostcondition);
      expect(f.severity, Severity.high);
      expect(f.subject, 'UC-02');
      expect(f.message, contains('UC-02'));
    });

    test('hyphen and "postconditions" forms both accepted', () {
      final doc = _doc([
        _useCase('UC-A', 'Flow.\nPost-condition: saved.'),
        _useCase('UC-B', 'Flow.\nPostconditions: archived.'),
        _useCase('UC-C', 'Flow.\npost conditions: logged.'),
      ]);
      expect(checks.missingPostcondition(doc), isEmpty);
    });

    test('Vietnamese "điều kiện sau" form accepted', () {
      final doc = _doc([
        _useCase('UC-VN', '''
Luồng chính:
  1. Người dùng chọn lớp.
Điều kiện sau: lớp được lưu vào hệ thống.'''),
      ]);
      expect(checks.missingPostcondition(doc), isEmpty);
    });

    test('mid-paragraph mention does NOT count as a heading', () {
      // "postcondition" appearing inline is not a marker — the goal is a
      // declarable end-state, not a passing reference.
      final doc = _doc([
        _useCase(
          'UC-MID',
          'Submit a draft. The system writes a postcondition log entry for '
              'every successful submit so audits can replay the run.',
        ),
      ]);
      final findings = checks.missingPostcondition(doc);
      expect(findings, hasLength(1));
      expect(findings.single.subject, 'UC-MID');
    });

    test('only use cases are inspected (FR ignored)', () {
      final doc = _doc([
        _fr(
          'FR-99',
          'The system shall export a PDF. Postcondition: file saved.',
        ),
      ]);
      expect(checks.missingPostcondition(doc), isEmpty);
    });

    test('OTES pattern: 3 UCs all missing postcondition → 3 findings', () {
      final doc = _doc([
        _useCase('UC-04', 'Use case #1 body, no Postcondition section.'),
        _useCase('UC-07', 'Use case #2 body, no Postcondition section.'),
        _useCase('UC-12', 'Use case #3 body, no Postcondition section.'),
      ]);
      final findings = checks.missingPostcondition(doc);
      expect(findings, hasLength(3));
      expect(findings.map((f) => f.subject), ['UC-04', 'UC-07', 'UC-12']);
    });
  });

  group('runAll', () {
    test('compose duplicateIds and missingPostcondition, no overlap', () {
      final doc = _doc([
        _useCase('UC-04', 'Use case A — no Postcondition.'),
        _useCase('UC-04', 'Use case B — no Postcondition.'),
      ]);
      final findings = checks.runAll(doc);
      // 1 duplicate id + 2 missing postconditions + 2 missing actors = 5
      // distinct findings. The three M2 checks now run in the same
      // ordered pipeline; the dedup-vs-postcondition math is preserved
      // and a new actor count joins.
      expect(findings, hasLength(5));
      expect(findings.map((f) => f.check).toSet(), {
        CheckId.duplicateIds,
        CheckId.missingPostcondition,
        CheckId.missingActor,
      });
    });
  });

  group('missingActor', () {
    test('UC with English Actor label passes', () {
      final doc = _doc([
        _useCase('UC-01', '''Use case 1.
Actor: Customer.
Steps:
  1. Customer logs in.
Postcondition: session active.
'''),
      ]);
      expect(const ReferenceChecks().missingActor(doc), isEmpty);
    });

    test('UC with Vietnamese Tác nhân label passes', () {
      final doc = _doc([
        _useCase('UC-02', '''Use case 2.
Tác nhân: Sinh viên.
Bước:
  1. Sinh viên đăng nhập.
Điều kiện sau: phiên hoạt động.
'''),
      ]);
      expect(const ReferenceChecks().missingActor(doc), isEmpty);
    });

    test('UC with no actor label is flagged', () {
      // The Vietnamese OTES shape: a use case that describes the flow
      // but never puts the role on a heading row.
      final doc = _doc([
        _useCase('UC-03', '''Use case 3.
Hệ thống cho phép đăng nhập bằng email.
Điều kiện sau: phiên hoạt động.
'''),
      ]);
      final findings = const ReferenceChecks().missingActor(doc);
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.missingActor);
      expect(findings.single.subject, 'UC-03');
      expect(findings.single.passed, isFalse);
      expect(findings.single.severity, Severity.high);
    });

    test('Primary actor label is also accepted', () {
      final doc = _doc([
        _useCase('UC-04', 'Primary actor: Admin.\nSteps: ...\n'),
      ]);
      expect(const ReferenceChecks().missingActor(doc), isEmpty);
    });

    test('statements (non-UC) are skipped', () {
      // RequirementKind.statement rows are not "use cases" — the
      // missing-actor check must not produce phantom findings on bare
      // requirement statements.
      final doc = _doc([_statement('The system shall persist the record.')]);
      expect(const ReferenceChecks().missingActor(doc), isEmpty);
    });

    test('mentions "actor" mid-paragraph do NOT pass', () {
      // The marker is the heading row. A sentence mid-paragraph that
      // uses the word is exactly the failure mode the check exists to
      // catch — the role was not declared, it was merely alluded to.
      final doc = _doc([
        _useCase(
          'UC-05',
          'The flow is initiated when the actor presses the button.',
        ),
      ]);
      final findings = const ReferenceChecks().missingActor(doc);
      expect(findings, hasLength(1));
      expect(findings.single.subject, 'UC-05');
    });
  });
}
