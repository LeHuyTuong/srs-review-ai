// Tests for the Word (.docx) twin — the format added 2026-09-25 because
// "export to docs" was the one output a supervisor opens and the app could not
// produce.
//
// What these pin, in priority order:
// 1. The container is a real OPC package: the seven parts exist, the content
//    types part comes first, and every part parses as XML. A .docx that misses
//    a part or carries a malformed one does not open in Word, and nothing else
//    in this repo would notice.
// 2. Escaping and encoding: document-derived text is untrusted, and it is
//    Vietnamese in practice. A quote holding `<`, `&` or a raw control byte
//    from a PDF text layer must not corrupt the part.
// 3. Honesty parity: the limitations section appears even for a run with no
//    result, and the offline layer keeps its PASS/FAIL state.
// 4. The binary save path: bytes reach the platform dialog unmodified.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/human_issue.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/services/report_exporter.dart';
import 'package:srs_review_ai/features/workspace/models/docx_report.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:xml/xml.dart';

WorkspaceUnit unit(String key, {UnitKind kind = UnitKind.useCase}) =>
    WorkspaceUnit(
      key: key,
      id: key,
      title: 'unit $key',
      text: 'The system shall do $key.',
      kind: kind,
      section: 'C. USE CASES',
      pageIndex: 4,
      malformed: false,
      selected: true,
    );

FindingRow row(String id, String quote) => FindingRow(
  id: id,
  unitKey: 'UC-01',
  requirementId: 'UC-01',
  pageIndex: 4,
  title: 'Đăng nhập',
  issue: ReviewIssue(
    type: IssueType.vagueness,
    severity: Severity.high,
    quote: quote,
    suggestion: 'Nêu ngưỡng đo được',
    verification: Verification.exact,
  ),
);

String partOf(Uint8List docx, String name) {
  final file = ZipDecoder().decodeBytes(docx).findFile(name);
  expect(file, isNotNull, reason: 'the package must contain $name');
  return utf8.decode(file!.content);
}

void main() {
  group('buildDocxReport — the package itself', () {
    final docx = buildDocxReport(
      fileName: 'otes.pdf',
      offline: true,
      result: null,
      units: [unit('UC-01')],
    );

    test('carries every part an OPC package needs', () {
      final archive = ZipDecoder().decodeBytes(docx);
      expect(archive.length, 7);
      for (final name in [
        '[Content_Types].xml',
        '_rels/.rels',
        'docProps/core.xml',
        'docProps/app.xml',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
      ]) {
        expect(archive.findFile(name), isNotNull, reason: name);
      }
    });

    test('puts [Content_Types].xml first — strict readers require it', () {
      final archive = ZipDecoder().decodeBytes(docx);
      expect(archive.files.first.name, '[Content_Types].xml');
    });

    test('every XML part parses', () {
      final archive = ZipDecoder().decodeBytes(docx);
      for (final file in archive.files) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content)),
          returnsNormally,
          reason: '${file.name} must be well-formed XML',
        );
      }
    });

    test('declares A4 portrait so the file prints without reformatting', () {
      final document = partOf(docx, 'word/document.xml');
      expect(document, contains('w:w="11906"'));
      expect(document, contains('w:h="16838"'));
    });
  });

  group('buildDocxReport — untrusted document text', () {
    test('keeps Vietnamese intact and escapes markup', () {
      final docx = buildDocxReport(
        fileName: 'báo cáo & mẫu.docx',
        offline: true,
        result: null,
        units: [unit('UC-01', kind: UnitKind.nonFunctional)],
        syllabusFindings: [
          DeterministicFinding(
            check: CheckId.placeholderTbd,
            passed: false,
            severity: Severity.medium,
            message: 'Còn "TBD" ở mục 4.2 — <cần điền>',
            subject: '§4.2',
          ),
        ],
      );
      final document = partOf(docx, 'word/document.xml');
      expect(document, contains('báo cáo &amp; mẫu.docx'));
      expect(document, contains('&lt;cần điền&gt;'));
      // The escaped text must survive a parser round trip as ONE text node —
      // proof the diacritics and the entities were not mangled on the way in.
      final parsed = XmlDocument.parse(document);
      expect(
        parsed.findAllElements('w:t').map((e) => e.innerText).join('|'),
        contains('báo cáo & mẫu.docx'),
      );
      expect(
        parsed.findAllElements('w:t').map((e) => e.innerText).join('|'),
        contains('<cần điền>'),
      );
    });

    test('drops control characters a PDF text layer really contains', () {
      final docx = buildDocxReport(
        fileName: 'dirty.pdf',
        offline: true,
        result: null,
        units: const [],
        humanIssues: [
          HumanIssue(
            id: 'h1',
            // 0x0B is legal in a PDF text layer and illegal in XML 1.0.
            title: 'Có byte điều khiển\u000B trong tiêu đề',
            detail: 'Không được phép giữ lại',
            severity: Severity.low,
            section: null,
            createdAt: DateTime.utc(2026, 9, 25),
          ),
        ],
      );
      final document = partOf(docx, 'word/document.xml');
      final text = XmlDocument.parse(
        document,
      ).findAllElements('w:t').map((e) => e.innerText).join('|');
      expect(text, isNot(contains('\u000B')));
      expect(
        text,
        contains('Có byte điều khiển trong tiêu đề'),
        reason: 'only the control byte is dropped, never the words',
      );
    });
  });

  group('buildDocxReport — the report contract', () {
    test('an empty run still states its limitations', () {
      final document = partOf(
        buildDocxReport(
          fileName: 'empty.pdf',
          offline: true,
          result: null,
          units: const [],
        ),
        'word/document.xml',
      );
      expect(document, contains('7. Limitations and evidence notes'));
      expect(document, contains('No scored sections in this run.'));
      expect(document, contains('offline mock (no model calls)'));
    });

    test('a finding keeps its quote, severity and page', () {
      final document = partOf(
        buildDocxReport(
          fileName: 'otes.pdf',
          offline: true,
          result: WorkspaceReviewResult(
            findings: [row('AMB-01', 'The system shall respond quickly.')],
            reviewed: 1,
            skipped: 0,
            failed: 0,
            droppedIssueCount: 0,
            mock: true,
            rubricVersion: 'v3',
            createdAt: DateTime.utc(2026, 9, 25),
            model: 'mock',
            scores: const {'UC-01': 7},
          ),
          units: [unit('UC-01')],
        ),
        'word/document.xml',
      );
      expect(document, contains('AMB-01'));
      expect(document, contains('The system shall respond quickly.'));
      expect(document, contains('page 5'));
      expect(document, contains('7.00'), reason: 'the average score is shown');
    });

    test('offline checks keep PASS and FAIL side by side', () {
      final document = partOf(
        buildDocxReport(
          fileName: 'otes.pdf',
          offline: true,
          result: null,
          units: const [],
          syllabusFindings: [
            DeterministicFinding(
              check: CheckId.ucCount,
              passed: false,
              severity: Severity.high,
              message: 'Only 12 use cases',
              subject: 'C. USE CASES',
              actual: 12,
              expectedMin: 20,
            ),
            DeterministicFinding(
              check: CheckId.language,
              passed: true,
              severity: Severity.low,
              message: 'English throughout',
            ),
          ],
        ),
        'word/document.xml',
      );
      expect(document, contains('PASS'));
      expect(document, contains('FAIL'));
      expect(document, contains('actual 12'));
      expect(document, contains('min 20'));
    });
  });

  test('the binary save path hands the bytes through untouched', () async {
    Uint8List? handed;
    String? mime;
    final exporter = ReportExporter(
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            required String dialogTitle,
          }) async {
            handed = bytes;
            mime = mimeType;
            return Uri.parse('file:///tmp/$fileName');
          },
    );

    final bytes = buildDocxReport(
      fileName: 'otes.pdf',
      offline: true,
      result: null,
      units: const [],
    );
    final destination = await exporter.saveBytes(
      fileName: 'report.docx',
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );

    expect(destination, 'file:///tmp/report.docx');
    expect(
      handed,
      bytes,
      reason: 'a ZIP must not be re-encoded on the way out',
    );
    expect(mime, contains('wordprocessingml.document'));
  });
}
