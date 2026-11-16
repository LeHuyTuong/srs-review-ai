/// The criterion an AI finding answers (2026-09-25).
///
/// The user-facing promise: a criterion a supervisor ADDED or EDITED in the
/// criteria list comes back on the findings they review — the id travels in
/// `criterion_id` (traceable to their row) while `type` carries the defect class.
/// Before the split, the prompt asked for the criterion id IN `type`, which is a
/// closed enum: the one value a user actually authored was the one value the
/// model could never return.
///
/// The companion promise is the server's, and is tested there
/// (server/tests/test_issue_labels.py): an unrecognised `type` is coerced to
/// `other` rather than failing the unit, so the closed vocabulary below stays
/// closed and [IssueType.fromWire] may keep rejecting anything else loudly.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';
import 'package:srs_review_ai/report_export/docx_report.dart';
import 'package:srs_review_ai/report_export/html_report.dart';
import 'package:srs_review_ai/report_export/report_export.dart';
import 'package:srs_review_ai/report_export/report_strings.dart';
import 'package:srs_review_ai/requirement_review/models/report_language.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart';
import 'package:srs_review_ai/requirement_review/models/workspace_findings.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';

const String kCriterion = 'nfr_quantified';

/// The exact shape the server's coercion produces when a model answers the old
/// way: the criterion id in `type`, and the class resolved to `other`.
Map<String, dynamic> coercedIssue() => {
  'type': 'other',
  'criterion_id': kCriterion,
  'severity': 'medium',
  'quote': 'Hệ thống phải nhanh.',
  'suggestion': 'Nêu ngưỡng đo được.',
  'verification': 'exact',
  'similarity': null,
};

ReviewIssue issue({String? criterionId = kCriterion, IssueType? type}) =>
    ReviewIssue(
      type: type ?? IssueType.other,
      severity: Severity.high,
      quote: 'Hệ thống phải nhanh.',
      suggestion: 'Nêu ngưỡng đo được.',
      verification: Verification.exact,
      criterionId: criterionId,
    );

FindingRow findingRow({String? criterionId = kCriterion}) => FindingRow(
  id: 'f1',
  unitKey: 'UC-01',
  requirementId: 'UC-01',
  pageIndex: 4,
  title: 'Đăng nhập',
  issue: issue(criterionId: criterionId),
);

WorkspaceUnit unit() => const WorkspaceUnit(
  key: 'UC-01',
  id: 'UC-01',
  title: 'Đăng nhập',
  text: 'Hệ thống cho phép đăng nhập.',
  kind: UnitKind.useCase,
  section: 'C. USE CASES',
  pageIndex: 4,
  malformed: false,
  selected: true,
);

String docxText(Uint8List bytes) => utf8.decode(
  ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
);

Map<String, String> renderAll(ReportLanguage language) {
  final units = [unit()];
  final findings = [findingRow()];
  final result = WorkspaceReviewResult(
    findings: findings,
    reviewed: 1,
    skipped: 0,
    failed: 0,
    droppedIssueCount: 0,
    mock: false,
    rubricVersion: kRubricLabel,
    createdAt: DateTime.utc(2026, 9, 25),
    scores: const {'UC-01': 5},
  );
  return {
    'markdown': buildMarkdownReport(
      fileName: 'otes.pdf',
      language: language,
      offline: false,
      result: result,
      units: units,
    ),
    'html': buildHtmlReport(
      fileName: 'otes.pdf',
      language: language,
      offline: false,
      result: result,
      units: units,
    ),
    'json': const JsonEncoder.withIndent('  ').convert(
      buildJsonReport(
        fileName: 'otes.pdf',
        language: language,
        offline: false,
        result: result,
        units: units,
      ),
    ),
    'docx': docxText(
      buildDocxReport(
        fileName: 'otes.pdf',
        language: language,
        offline: false,
        result: result,
        units: units,
      ),
    ),
  };
}

void main() {
  group('the wire shape', () {
    test('criterion_id is optional and survives a round trip', () {
      final parsed = ReviewIssue.fromJson(coercedIssue());

      expect(parsed.type, IssueType.other);
      expect(parsed.criterionId, kCriterion);
      expect(ReviewIssue.fromJson(parsed.toJson()).criterionId, kCriterion);
    });

    test(
      'an issue with no criterion reads back as null, not as an empty id',
      () {
        final payload = coercedIssue()..remove('criterion_id');

        expect(ReviewIssue.fromJson(payload).criterionId, isNull);
        expect(ReviewIssue.fromJson(issue().toJson()).criterionId, kCriterion);
        expect(
          ReviewIssue.fromJson(issue(criterionId: null).toJson()).criterionId,
          isNull,
        );
      },
    );

    test('a finding row keeps the criterion id through a session payload', () {
      final row = findingRow();

      expect(FindingRow.fromJson(row.toJson()).issue.criterionId, kCriterion);
    });

    test('the Dart enum is exactly the schema enum, in the schema order', () {
      // The schema is what the server publishes and the app accepts; nothing
      // else compares the two lists, and a member added on one side only is the
      // drift that turns into a ContractException in the field.
      final schema =
          jsonDecode(File('../contracts/review.schema.json').readAsStringSync())
              as Map<String, dynamic>;
      final defs = schema[r'$defs'] as Map<String, dynamic>;
      final declared =
          (defs['IssueType'] as Map<String, dynamic>)['enum'] as List;

      expect(declared, IssueType.values.map((t) => t.name).toList());
      expect(
        (defs['Severity'] as Map<String, dynamic>)['enum'],
        Severity.values.map((s) => s.name).toList(),
      );
      // `criterion_id` must be a declared property: `additionalProperties` is
      // false, so an undeclared key would be a contract violation.
      final issueProps =
          ((defs['Issue'] as Map<String, dynamic>)['properties'])
              as Map<String, dynamic>;
      expect(issueProps.keys, contains('criterion_id'));
    });

    test(
      'an unknown type is still rejected — the server coerces, the app does not',
      () {
        final payload = coercedIssue()..['type'] = 'brand_new_category';

        expect(
          () => ReviewIssue.fromJson(payload),
          throwsA(isA<ContractException>()),
        );
      },
    );
  });

  group('labels', () {
    test('other is named in both languages, and as a rubric problem', () {
      const vi = ReportStrings(ReportLanguage.vietnamese);
      const en = ReportStrings(ReportLanguage.english);

      expect(vi.issueTypeLabel(IssueType.other), 'Khác');
      expect(en.issueTypeLabel(IssueType.other), 'Other');
      // Not 'chưa phân loại' — that label belongs to units the PARSER could not
      // classify, and reusing it would read as a parsing problem.
      expect(
        vi.issueTypeLabel(IssueType.other),
        isNot(vi.unitKindLabel(UnitKind.unknown)),
      );
      expect(workspaceLabel('other'), 'Khác');
      for (final type in IssueType.values) {
        expect(
          vi.issueTypeLabel(type),
          isNot(en.issueTypeLabel(type)),
          reason: '${type.name} reads the same in both languages',
        );
      }
    });

    test('the criterion reference keeps the id verbatim', () {
      const vi = ReportStrings(ReportLanguage.vietnamese);
      const en = ReportStrings(ReportLanguage.english);

      expect(vi.criterionRef(kCriterion), 'tiêu chí: $kCriterion');
      expect(en.criterionRef(kCriterion), 'criterion: $kCriterion');
    });
  });

  group('every report names the criterion', () {
    for (final language in ReportLanguage.values) {
      test('${language.wire}: the criterion id reaches all four formats', () {
        for (final entry in renderAll(language).entries) {
          expect(
            entry.value,
            contains(kCriterion),
            reason: '${entry.key} dropped the criterion id',
          );
        }
      });
    }

    test('the markdown and HTML twins label it in the report language', () {
      final vi = renderAll(ReportLanguage.vietnamese);
      final en = renderAll(ReportLanguage.english);

      expect(vi['markdown'], contains('`tiêu chí: $kCriterion`'));
      expect(en['markdown'], contains('`criterion: $kCriterion`'));
      expect(vi['html'], contains('tiêu chí: $kCriterion'));
      expect(en['html'], contains('criterion: $kCriterion'));
      expect(vi['docx'], contains('tiêu chí: $kCriterion'));
      expect(en['docx'], contains('criterion: $kCriterion'));
    });

    test('the JSON keeps it as a lookup key beside the other tokens', () {
      final payload =
          jsonDecode(renderAll(ReportLanguage.vietnamese)['json']!)
              as Map<String, dynamic>;
      final issue =
          ((payload['findings'] as List).first as Map)['criterion_id'];

      expect(issue, kCriterion);
    });

    test('a finding with no criterion prints no empty reference', () {
      final markdown = buildMarkdownReport(
        fileName: 'otes.pdf',
        language: ReportLanguage.vietnamese,
        offline: false,
        result: WorkspaceReviewResult(
          findings: [findingRow(criterionId: null)],
          reviewed: 1,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: kRubricLabel,
          createdAt: DateTime.utc(2026, 9, 25),
        ),
        units: [unit()],
      );

      expect(markdown, contains('## Lỗi phát hiện'));
      expect(markdown, isNot(contains('tiêu chí:')));
    });
  });

  test('the app-side offline mock cites a criterion too', () {
    // Offline demo mode runs its own rule engine (no proxy at all); it names the
    // seed criterion each of its rules implements, so a demo with no server
    // still shows where a finding came from.
    final result = MockReviewApi.score(
      requirementId: 'FR-03',
      text: 'The system shall respond quickly to every search request.',
    );

    expect(result.issues, isNotEmpty);
    expect(result.issues.first.criterionId, 'unambiguous');
  });

  test('the deterministic ledger is untouched by the AI criterion field', () {
    // Guard against the two vocabularies getting mixed: a rubric criterion id
    // belongs on an AI finding, and a CheckId belongs on a rule finding.
    final finding = DeterministicFinding.both(
      check: CheckId.nfrUnquantified,
      passed: false,
      severity: Severity.high,
      message: 'msg',
    );
    final markdown = buildMarkdownReport(
      fileName: 'otes.pdf',
      language: ReportLanguage.vietnamese,
      offline: false,
      result: null,
      units: const [],
      syllabusFindings: [finding],
    );

    expect(markdown, contains('NFR không có ngưỡng đo'));
    expect(markdown, isNot(contains('tiêu chí:')));
  });
}
