/// §F.3/F.4 (rulebook 1.7-draft) — the two checks that need evidence the
/// document cannot supply about itself: a human declaration vs the printed
/// cover, and the resolved chapter ranges vs each other.
///
/// The property under test most often here is SILENCE: no declaration, a
/// scanned cover, an untrusted index — none of these is a defect of the
/// document, and a check that guesses would poison the ledger with findings
/// nobody can act on (hard rule 3: a part we could not read is never
/// reported).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/project_info_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/document_blueprint.dart';
import 'package:srs_review_ai/document_import/models/project_info.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;

/// A readable two-page cover: page 0 carries title + supervisor, page 1 the
/// student line. Comfortably above the 3-line scan gate.
const List<String> _cover = [
  'FPT University\nOnline Tutoring Examination System\n'
      'SRS Document v1.0\nSupervisor: Nguyen Van A',
  'Student: Tran B — SE123456',
];

ProjectInfo _declared({
  String projectName = 'Online Tutoring Examination System',
  String? supervisor = 'Nguyen Van A',
}) => ProjectInfo(
  projectName: projectName,
  students: const [StudentMember(fullName: 'Tran B', studentId: 'SE123456')],
  supervisor: supervisor,
);

SectionRange _range(String id, int start, int end) => SectionRange(
  id: id,
  title: 'Chapter $id',
  printedStart: start,
  printedEnd: end,
  pdfStartIndex: start,
  pdfEndIndex: end,
);

DocumentBlueprint _blueprint(
  List<SectionRange> sections, {
  required bool trusted,
}) => DocumentBlueprint(
  sections: sections,
  artifacts: const [],
  pageOffset: 0,
  tocPageIndexes: const {},
  trusted: trusted,
);

void main() {
  const checks = ProjectInfoChecks();

  group('§F.3 declaredVsCover', () {
    test('declaration the cover confirms → silent', () {
      expect(checks.declaredVsCover(_declared(), _cover), isEmpty);
    });

    test('nothing declared → silent (the form is optional)', () {
      expect(
        checks.runAll(declared: null, pageTexts: _cover),
        isEmpty,
        reason: 'an empty form is not a document defect',
      );
    });

    test('title absent from the cover → one HIGH finding naming the title', () {
      final findings = checks.declaredVsCover(
        _declared(projectName: 'Quantum Flux Capacitor Examulator'),
        _cover,
      );
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.projectInfoMismatch);
      expect(findings.single.severity, Severity.high);
      expect(findings.single.subject, 'title');
      expect(findings.single.passed, isFalse);
      // The message must carry BOTH sides of the comparison so the reader
      // can act on it without re-opening the form.
      expect(
        findings.single.messageVi,
        contains('Quantum Flux Capacitor Examulator'),
      );
      expect(findings.single.messageVi, contains('0/'));
    });

    test('supervisor missing, title matches → MEDIUM, one finding', () {
      final findings = checks.declaredVsCover(
        _declared(supervisor: 'Ghost Advisor'),
        _cover,
      );
      expect(findings, hasLength(1));
      expect(findings.single.severity, Severity.medium);
      expect(findings.single.subject, 'supervisor');
      expect(findings.single.messageVi, contains('Ghost Advisor'));
    });

    test('both wrong → exactly two findings, one per field', () {
      final findings = checks.declaredVsCover(
        _declared(
          projectName: 'Quantum Flux Capacitor Examulator',
          supervisor: 'Ghost Advisor',
        ),
        _cover,
      );
      expect(findings, hasLength(2));
      expect(
        findings.map((f) => f.subject),
        containsAll(['title', 'supervisor']),
      );
    });

    test('scanned cover (< 3 readable lines) → silent, even when wrong', () {
      // A part we could not read is never reported as clean OR as broken —
      // it is reported nowhere; the coverage header is what says so.
      final findings = checks.declaredVsCover(
        _declared(projectName: 'Totally Elsewhere Thing'),
        const ['only two', 'lines here'],
      );
      expect(findings, isEmpty);
    });

    test('empty pageTexts (no document yet) → silent', () {
      expect(checks.declaredVsCover(_declared(), const []), isEmpty);
    });
  });

  group('§F.4 sectionOrder', () {
    test('monotonic chapters → silent', () {
      final blueprint = _blueprint([
        _range('A', 1, 9),
        _range('B', 10, 21),
        _range('C', 22, 30),
      ], trusted: true);
      expect(checks.sectionOrder(blueprint), isEmpty);
    });

    // Boundary semantics pinned explicitly: start == previous end passes,
    // only start < previous end is a defect.
    test('chapter starting exactly where the previous ends → silent', () {
      final blueprint = _blueprint([
        _range('A', 1, 10),
        _range('B', 10, 21),
      ], trusted: true);
      expect(checks.sectionOrder(blueprint), isEmpty);
    });

    test('chapter starting inside its predecessor → one MEDIUM finding', () {
      final blueprint = _blueprint([
        _range('A', 1, 15),
        _range('B', 10, 25),
      ], trusted: true);
      final findings = checks.sectionOrder(blueprint);
      expect(findings, hasLength(1));
      expect(findings.single.check, CheckId.sectionOrder);
      expect(findings.single.severity, Severity.medium);
      expect(findings.single.subject, 'A->B');
      // Both parts named, with their printed spans — the whole claim is in
      // the message, like every other deterministic finding.
      expect(findings.single.messageVi, contains('"A Chapter A"'));
      expect(findings.single.messageVi, contains('"B Chapter B"'));
      expect(findings.single.messageVi, contains('15'));
      expect(findings.single.messageVi, contains('10'));
    });

    test('every overlapping pair in a chain is reported', () {
      final blueprint = _blueprint([
        _range('A', 1, 30),
        _range('B', 10, 40),
        _range('C', 20, 50),
      ], trusted: true);
      final findings = checks.sectionOrder(blueprint);
      expect(findings.map((f) => f.subject), ['A->B', 'B->C']);
    });

    test('untrusted index → silent (a guess is not a finding)', () {
      final blueprint = _blueprint([
        _range('A', 1, 15),
        _range('B', 10, 25),
      ], trusted: false);
      expect(checks.sectionOrder(blueprint), isEmpty);
    });

    test('null blueprint (DOCX / index-less PDF) → silent', () {
      expect(checks.sectionOrder(null), isEmpty);
      expect(checks.runAll(declared: _declared(), pageTexts: _cover), isEmpty);
    });
  });
}
