/// Pins the one promise the export dialog makes about language: a report is
/// fully English or fully Vietnamese, never half of each.
///
/// Why a whole file for it: the mix used to be invisible. Each check engine
/// authored its message in whichever language its author used, and the report
/// scaffolding was English, so the default export read as Vietnamese prose with
/// English headings and English limitation paragraphs. Nothing in the compiler
/// flags a Spanish literal, and nothing in a screenshot flags one either — the
/// failure mode is a reader noticing two languages in one file.
///
/// What is asserted, in priority order:
/// 1. Every one of the four formats renders in the chosen language and carries
///    no prose from the other one. Machine tokens (`reason=…`, enum names, JSON
///    keys) are not prose and are deliberately exempt — see the JSON group.
/// 2. One switch flips all four, and the app's default is Vietnamese.
/// 3. Evidence is never translated: the document's own quote and the model's
///    suggestion come through byte-for-byte in both languages.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/human_issue.dart';
import 'package:srs_review_ai/data/models/report_language.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/docx_report.dart';
import 'package:srs_review_ai/features/workspace/models/html_report.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/report_strings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

// --------------------------------------------------------------- the fixture
//
// Deliberately mixed on purpose: the DOCUMENT's own text is Vietnamese (as the
// OTES SRS is) and the reviewer's own note is English. Both are evidence, so
// both must survive untouched in EITHER report language — which is exactly why
// the "no foreign prose" scan below cannot simply look for Vietnamese
// characters or English words in the whole file. It looks for the report's own
// scaffolding sentences, the ones the builders author.

const String kQuote = 'Hệ thống phải xử lý nhanh.';
const String kSuggestion =
    'Quote the measurable threshold the reader must hit.';
const String kHumanTitle = 'Reviewer note: missing threshold';

WorkspaceUnit unit(String id) => WorkspaceUnit(
  key: id,
  id: id,
  title: 'Đăng nhập hệ thống',
  text: 'Hệ thống cho phép người dùng đăng nhập bằng email.',
  kind: UnitKind.useCase,
  section: 'C. USE CASES',
  pageIndex: 4,
  malformed: false,
  selected: true,
  status: UnitStatus.reviewed,
);

FindingRow row(String id) => FindingRow(
  id: id,
  unitKey: 'UC-01',
  requirementId: 'UC-01',
  pageIndex: 4,
  title: 'Đăng nhập hệ thống',
  issue: const ReviewIssue(
    type: IssueType.vagueness,
    severity: Severity.high,
    quote: kQuote,
    suggestion: kSuggestion,
    verification: Verification.exact,
  ),
);

/// One finding per offline family, so each family label and message reaches the
/// report — and so a family labelled in only one language is caught here.
DeterministicFinding check(CheckId id, {bool passed = false}) =>
    DeterministicFinding(
      check: id,
      passed: passed,
      severity: Severity.high,
      messageEn: 'Message for ${id.wire}',
      messageVi: 'Thông điệp cho ${id.wire}',
      subject: 'UC-01',
    );

final WorkspaceReviewResult kResult = WorkspaceReviewResult(
  findings: [row('f1')],
  reviewed: 1,
  skipped: 0,
  failed: 0,
  droppedIssueCount: 1,
  mock: false,
  rubricVersion: kRubricLabel,
  createdAt: DateTime.utc(2026, 9, 25),
  model: 'gemini-3-flash',
  scores: const {'UC-01': 4},
);

final List<HumanIssue> kHumanIssues = [
  HumanIssue(
    id: 'h1',
    title: kHumanTitle,
    detail: 'Needs a number.',
    severity: Severity.medium,
    section: '4.2',
    createdAt: DateTime.utc(2026, 9, 25, 10, 30),
  ),
];

const PageImageCoverage kCoverage = PageImageCoverage(
  candidates: 2,
  extracted: 1,
  reviewed: 1,
  skipped: 1,
  failed: 0,
  reasons: {'no-diagram-intent': 1},
);

/// Every format, rendered from one identical input, so a language that reached
/// three builders out of four is visible as one entry in this map disagreeing.
Map<String, String> renderEverything(ReportLanguage language) {
  final units = [unit('UC-01')];
  final docx = buildDocxReport(
    fileName: 'otes.pdf',
    language: language,
    offline: false,
    result: kResult,
    units: units,
    syllabusFindings: [
      check(CheckId.ucCount),
      check(CheckId.ucSize, passed: true),
    ],
    referenceFindings: [check(CheckId.missingPostcondition)],
    blueprintFindings: [check(CheckId.numberingGap)],
    diagramPageCount: 3,
    imageReviewAvailable: true,
    imageReviewedCount: 1,
    imageCoverage: kCoverage,
    humanIssues: kHumanIssues,
  );
  return {
    'markdown': buildMarkdownReport(
      fileName: 'otes.pdf',
      language: language,
      offline: false,
      result: kResult,
      units: units,
      syllabusFindings: [
        check(CheckId.ucCount),
        check(CheckId.ucSize, passed: true),
      ],
      referenceFindings: [check(CheckId.missingPostcondition)],
      blueprintFindings: [check(CheckId.numberingGap)],
      diagramPageCount: 3,
      imageReviewAvailable: true,
      imageReviewedCount: 1,
      imageCoverage: kCoverage,
      humanIssues: kHumanIssues,
    ),
    'html': buildHtmlReport(
      fileName: 'otes.pdf',
      language: language,
      offline: false,
      result: kResult,
      units: units,
      syllabusFindings: [
        check(CheckId.ucCount),
        check(CheckId.ucSize, passed: true),
      ],
      referenceFindings: [check(CheckId.missingPostcondition)],
      blueprintFindings: [check(CheckId.numberingGap)],
      diagramPageCount: 3,
      imageReviewAvailable: true,
      imageReviewedCount: 1,
      imageCoverage: kCoverage,
      humanIssues: kHumanIssues,
    ),
    'json': const JsonEncoder.withIndent('  ').convert(
      buildJsonReport(
        fileName: 'otes.pdf',
        language: language,
        offline: false,
        result: kResult,
        units: units,
        syllabusFindings: [
          check(CheckId.ucCount),
          check(CheckId.ucSize, passed: true),
        ],
        referenceFindings: [check(CheckId.missingPostcondition)],
        blueprintFindings: [check(CheckId.numberingGap)],
        diagramPageCount: 3,
        imageReviewAvailable: true,
        imageReviewedCount: 1,
        imageCoverage: kCoverage,
        humanIssues: kHumanIssues,
      ),
    ),
    // A .docx is a ZIP; the parts a reader can see are the two XML ones. The
    // document properties count: Word shows that title in its window bar.
    'docx': [
      _part(docx, 'word/document.xml'),
      _part(docx, 'docProps/core.xml'),
    ].join('\n'),
  };
}

// A plain throw, not `expect`: this is called while the group body runs, before
// the test binding exists, and `expect` there aborts the whole file with
// OutsideTestException instead of naming the missing part.
String _part(Uint8List docx, String name) {
  final file = ZipDecoder().decodeBytes(docx).findFile(name);
  if (file == null) throw StateError('the package must contain $name');
  return utf8.decode(file.content);
}

/// Sentences the BUILDERS author, never the document. Every entry is prose a
/// reader would notice sitting in the wrong language; machine tokens
/// (`reason=no-diagram-intent`, `offline_mock`, `high`, `pending`, JSON keys)
/// are deliberately absent — those are a contract, not a language.
const List<String> kEnglishScaffolding = [
  '# SRS Review Report',
  'SRS review report',
  '## Coverage',
  '## Verdict',
  '## Scores by section',
  '## Deterministic checks',
  '## Findings',
  '## Inventory',
  '## Human-reported issues',
  '## Limitations & future work',
  '| **Document** |',
  'Report language: English',
  'Reviewed | Skipped | Failed',
  'The last review run',
  'selected unit(s) returned results',
  'No findings yet',
  'Priority coverage',
  'No OCR',
  'Offline mock',
  'Online proxy',
  'Full ledger',
  'needs vision evidence',
  'Generated by SRS Review AI',
  'app rubric v3',
  'whole document',
  '1. Run summary',
  '2. Scores by document section',
  '3. Findings from the review model',
  '4. Offline checks',
  '5. Issues recorded by the reviewer',
  '6. Document inventory',
  '7. Limitations and evidence notes',
  'Not run for this document.',
  'This section is not optional.',
  'Avg /10',
];

const List<String> kVietnameseScaffolding = [
  '# Báo cáo đánh giá SRS',
  'Báo cáo đánh giá SRS',
  '## Phạm vi đánh giá',
  '## Kết luận',
  '## Điểm theo mục',
  '## Kiểm tra bằng luật',
  '## Lỗi phát hiện',
  '## Danh mục tài liệu',
  '## Lỗi do người review ghi',
  '## Giới hạn & hướng tiếp theo',
  'Ngôn ngữ báo cáo: Tiếng Việt',
  'Lượt chấm gần nhất',
  'mục đã chọn trả về kết quả',
  'Chưa có lỗi nào',
  'Không OCR',
  'Mô phỏng ngoại tuyến',
  'Trực tuyến qua proxy',
  'Sổ theo dõi đầy đủ',
  'cần bằng chứng hình ảnh',
  'Do SRS Review AI tạo',
  'thang điểm app v3',
  'toàn tài liệu',
  '1. Tóm tắt lượt chấm',
  '2. Điểm theo mục tài liệu',
  '3. Lỗi do model phát hiện',
  '4. Kiểm tra ngoại tuyến',
  '5. Lỗi do người review ghi',
  '6. Danh mục tài liệu',
  '7. Giới hạn và ghi chú bằng chứng',
  'Không chạy cho tài liệu này.',
  'Mục này không được bỏ.',
  'TB /10',
];

/// Markers a format is ALLOWED to carry in the other language.
///
/// One entry, and it is not a loophole: the JSON twin's `rubric_version` is a
/// key a script reads, so it stays the stable identifier while every
/// human-readable value beside it follows the language. The prose formats
/// localize the same string for display and are held to it.
const Map<String, List<String>> kExempt = {
  'json': ['app rubric v3'],
};

void _expectNoneOf(
  String haystack,
  List<String> needles,
  String label, {
  List<String> except = const [],
}) {
  final found = needles
      .where((needle) => !except.contains(needle))
      .where(haystack.contains)
      .toList(growable: false);
  expect(
    found,
    isEmpty,
    reason:
        '$label carries ${found.length} string(s) from the other language: '
        '${found.join(' | ')}',
  );
}

void main() {
  group('every format is written in exactly one language', () {
    final vietnamese = renderEverything(ReportLanguage.vietnamese);
    final english = renderEverything(ReportLanguage.english);

    for (final format in vietnamese.keys) {
      test('$format: Vietnamese report carries no English prose', () {
        _expectNoneOf(
          vietnamese[format]!,
          kEnglishScaffolding,
          'the Vietnamese $format',
          except: kExempt[format] ?? const [],
        );
      });

      test('$format: English report carries no Vietnamese prose', () {
        _expectNoneOf(
          english[format]!,
          kVietnameseScaffolding,
          'the English $format',
          except: kExempt[format] ?? const [],
        );
      });
    }

    test('the two renderings actually differ in every format', () {
      // Guards the tripwires above from passing for the wrong reason: if a
      // builder silently ignored `language`, both scans would pass and the
      // report would be one language for everyone.
      for (final format in vietnamese.keys) {
        expect(
          vietnamese[format],
          isNot(english[format]),
          reason: '$format ignores the report language',
        );
      }
    });

    test('the offline-only sections are localized too', () {
      // The fixture above is an online run with a result, so the mock-mode
      // warning, the empty-run warning and the "run produced no findings" line
      // never render. They are separate sentences in each builder and each one
      // used to be English-only, so they get their own pass with an offline run
      // that returned nothing.
      final vi = buildMarkdownReport(
        fileName: 'otes.pdf',
        language: ReportLanguage.vietnamese,
        offline: true,
        result: null,
        units: const [],
      );
      final en = buildMarkdownReport(
        fileName: 'otes.pdf',
        language: ReportLanguage.english,
        offline: true,
        result: null,
        units: const [],
      );
      _expectNoneOf(vi, kEnglishScaffolding, 'the empty Vietnamese report');
      _expectNoneOf(en, kVietnameseScaffolding, 'the empty English report');
      expect(vi, contains('Mô phỏng ngoại tuyến'));
      expect(en, contains('Offline mock'));
    });
  });

  group('the JSON twin keeps its machine contract', () {
    // The JSON is the one format where the two languages legitimately coexist:
    // the KEYS and the enum tokens a script filters on are the schema, and a
    // schema that moved with a UI switch would break every reader. Only the
    // human-readable VALUES follow the language.
    final vi = buildJsonReport(
      fileName: 'otes.pdf',
      language: ReportLanguage.vietnamese,
      offline: false,
      result: kResult,
      units: [unit('UC-01')],
      syllabusFindings: [check(CheckId.ucCount)],
      referenceFindings: [check(CheckId.missingPostcondition)],
      blueprintFindings: [check(CheckId.numberingGap)],
      imageCoverage: kCoverage,
      humanIssues: kHumanIssues,
    );
    final en = buildJsonReport(
      fileName: 'otes.pdf',
      language: ReportLanguage.english,
      offline: false,
      result: kResult,
      units: [unit('UC-01')],
      syllabusFindings: [check(CheckId.ucCount)],
      referenceFindings: [check(CheckId.missingPostcondition)],
      blueprintFindings: [check(CheckId.numberingGap)],
      imageCoverage: kCoverage,
      humanIssues: kHumanIssues,
    );

    test('the two languages produce the identical key tree', () {
      expect(_keyPaths(vi), _keyPaths(en));
    });

    test('the language is declared, and the enum tokens never move', () {
      expect(vi['report_language'], 'vi');
      expect(en['report_language'], 'en');
      for (final report in [vi, en]) {
        expect(report['schema'], 'srs-review/report');
        expect(report['x-schema-version'], '1.0.0');
        expect(
          (report['document'] as Map<String, dynamic>)['mode'],
          'online_proxy',
        );
        final findings = (report['findings'] as List)
            .cast<Map<String, dynamic>>();
        expect(findings.single['severity'], 'high');
        expect(findings.single['status'], 'open');
      }
    });

    test('every human-readable value follows the language', () {
      final viLimits = (vi['limitations'] as List).cast<String>();
      final enLimits = (en['limitations'] as List).cast<String>();
      expect(viLimits.length, enLimits.length);
      for (var i = 0; i < viLimits.length; i++) {
        expect(
          viLimits[i],
          isNot(enLimits[i]),
          reason: 'limitation #$i was never translated',
        );
      }
      _expectNoneOf(viLimits.join('\n'), kEnglishScaffolding, 'vi limitations');
      _expectNoneOf(
        enLimits.join('\n'),
        kVietnameseScaffolding,
        'en limitations',
      );

      final viMessages = (vi['deterministic_checks'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['message']! as String);
      final enMessages = (en['deterministic_checks'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['message']! as String);
      for (final message in viMessages) {
        expect(message, contains('Thông điệp cho'));
      }
      for (final message in enMessages) {
        expect(message, contains('Message for'));
      }
    });
  });

  group('evidence is quoted, never translated', () {
    test('the document quote and the AI suggestion survive both languages', () {
      for (final language in ReportLanguage.values) {
        final markdown = renderEverything(language)['markdown']!;
        expect(markdown, contains('> $kQuote'));
        expect(markdown, contains(kSuggestion));
        expect(markdown, contains(kHumanTitle));
        // The quote is the document speaking: whichever report language was
        // picked, the reviewer must read the sentence that is actually in the
        // SRS, not a paraphrase of it.
        expect(
          markdown,
          isNot(contains('Hệ thống phải xử lý nhanh, có thể đo')),
        );
      }
    });

    test('the language note warns the reader about exactly that', () {
      for (final language in ReportLanguage.values) {
        final markdown = renderEverything(language)['markdown']!;
        expect(markdown, contains(ReportStrings(language).languageNote));
      }
    });
  });

  group('ReportStrings', () {
    test('every CheckId has a label in both languages, and they differ', () {
      const vi = ReportStrings(ReportLanguage.vietnamese);
      const en = ReportStrings(ReportLanguage.english);
      for (final check in CheckId.values) {
        expect(vi.checkLabel(check), isNotEmpty, reason: '${check.wire} vi');
        expect(en.checkLabel(check), isNotEmpty, reason: '${check.wire} en');
        expect(
          vi.checkLabel(check),
          isNot(en.checkLabel(check)),
          reason:
              '${check.wire} reads the same in both languages — '
              'a check added with only one authoring language',
        );
      }
    });

    test('a unit status never prints the raw enum name', () {
      const vi = ReportStrings(ReportLanguage.vietnamese);
      for (final status in UnitStatus.values) {
        expect(vi.unitStatusLabel(status.name), isNot(status.name));
      }
    });
  });

  group('one switch, all four exports', () {
    test('the app default is Vietnamese and the switch flips every format', () {
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);

      expect(
        container.read(workspaceViewModelProvider).reportLanguage,
        ReportLanguage.vietnamese,
        reason: 'the app default lives in the VM, not in the builders',
      );

      List<String> everything() => [
        vm.exportMarkdown(),
        vm.exportHtml(),
        vm.exportJson(),
        _part(vm.exportDocx(), 'word/document.xml'),
      ];

      final vi = everything();
      vm.setReportLanguage(ReportLanguage.english);
      final en = everything();

      for (var i = 0; i < vi.length; i++) {
        expect(
          vi[i],
          isNot(en[i]),
          reason: 'export #$i did not follow the switch',
        );
      }
      expect(vi[0], contains('# Báo cáo đánh giá SRS'));
      expect(en[0], contains('# SRS Review Report'));
      expect(vi[1], contains('<html lang="vi">'));
      expect(en[1], contains('<html lang="en">'));
      expect(vi[2], contains('"report_language": "vi"'));
      expect(en[2], contains('"report_language": "en"'));
    });

    test('the export file name carries the language', () {
      // Two languages, two files: a team exporting both copies of one run used
      // to get one silently overwriting the other in the Downloads folder.
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      expect(vm.reportFileName(), contains('-vi-'));
      vm.setReportLanguage(ReportLanguage.english);
      expect(vm.reportFileName(), contains('-en-'));
    });
  });

  group('the choice survives a restart', () {
    // The draft is an opaque JSON string the VM owns, so the round trip is
    // set → (restart: a fresh container over the SAME store) → read.

    /// Pumps the microtask/event queue until the draft restore lands — the
    /// read is async, so the first read after creating the container can
    /// legitimately still hold the default. The bounded loop keeps a broken
    /// restore a fast failure at the test's own assertion instead of a hang.
    Future<void> pumpUntilRestored(
      ProviderContainer container,
      bool Function(WorkspaceState) predicate,
    ) async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
        if (predicate(container.read(workspaceViewModelProvider))) return;
      }
    }

    test('an English choice is restored after a restart', () async {
      final store = InMemorySessionStore();
      final containerA = ProviderContainer(
        overrides: [sessionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(containerA.dispose);
      containerA
          .read(workspaceViewModelProvider.notifier)
          .setReportLanguage(ReportLanguage.english);
      // The draft write is fire-and-forget: pump once, then pin that it did
      // land — a silent no-op write must fail here, not downstream.
      await Future<void>.delayed(Duration.zero);
      expect(await store.loadDraft(), contains('"reportLanguage":"en"'));

      // A fresh container over the SAME store is the restart.
      final containerB = ProviderContainer(
        overrides: [sessionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(containerB.dispose);
      await pumpUntilRestored(
        containerB,
        (state) => state.reportLanguage == ReportLanguage.english,
      );
      expect(
        containerB.read(workspaceViewModelProvider).reportLanguage,
        ReportLanguage.english,
      );
    });

    test(
      'a draft written before the field existed keeps the default',
      () async {
        // Absence of the key is "no preference recorded", not Vietnamese-as-a-
        // choice: the restore must not map absence through fromWire and must
        // still restore the fields the draft DOES carry.
        final store = InMemorySessionStore();
        await store.saveDraft(jsonEncode({'projectName': 'Đợt cũ'}));
        final container = ProviderContainer(
          overrides: [sessionStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        await pumpUntilRestored(
          container,
          (state) => state.projectName.isNotEmpty,
        );
        final state = container.read(workspaceViewModelProvider);
        expect(state.reportLanguage, ReportLanguage.vietnamese);
        expect(state.projectName, 'Đợt cũ');
      },
    );

    test('a corrupt wire value falls back to the app default', () async {
      final store = InMemorySessionStore();
      await store.saveDraft(jsonEncode({'reportLanguage': 'fr'}));
      final container = ProviderContainer(
        overrides: [sessionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // Nothing observable flips — a corrupt value must degrade to the
      // default, never crash the startup over a preference.
      await pumpUntilRestored(container, (_) => false);
      expect(
        container.read(workspaceViewModelProvider).reportLanguage,
        ReportLanguage.vietnamese,
      );
    });

    test(
      'an explicit Vietnamese choice is restored, not treated as absence',
      () async {
        // English then back to Vietnamese: the draft now carries 'vi' as a
        // deliberate choice. Restoring it through fromWire and restoring it as
        // "no preference" happen to agree today — this test pins that the WIRE
        // is what round-trips, so a future default change cannot silently turn
        // every stored 'vi' into "whatever the new default is".
        final store = InMemorySessionStore();
        final containerA = ProviderContainer(
          overrides: [sessionStoreProvider.overrideWithValue(store)],
        );
        addTearDown(containerA.dispose);
        final vmA = containerA.read(workspaceViewModelProvider.notifier);
        vmA.setReportLanguage(ReportLanguage.english);
        vmA.setReportLanguage(ReportLanguage.vietnamese);
        await Future<void>.delayed(Duration.zero);
        expect(await store.loadDraft(), contains('"reportLanguage":"vi"'));

        final containerB = ProviderContainer(
          overrides: [sessionStoreProvider.overrideWithValue(store)],
        );
        addTearDown(containerB.dispose);
        await pumpUntilRestored(
          containerB,
          (state) => state.reportLanguage == ReportLanguage.vietnamese,
        );
        expect(
          containerB.read(workspaceViewModelProvider).reportLanguage,
          ReportLanguage.vietnamese,
        );
      },
    );

    test(
      'the draft stays preference-only: no workspace fields leak in',
      () async {
        // AGENTS.md rule: the draft never carries units/findings/result. A new
        // key sliding the workspace in would recreate the megabyte write-once-
        // read-never snapshot this draft replaced.
        final store = InMemorySessionStore();
        final container = ProviderContainer(
          overrides: [sessionStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        container
            .read(workspaceViewModelProvider.notifier)
            .setReportLanguage(ReportLanguage.english);
        await Future<void>.delayed(Duration.zero);
        final raw = await store.loadDraft();
        final payload = jsonDecode(raw!) as Map<String, dynamic>;
        expect(payload.keys.toSet(), {
          'projectName',
          'projectInfo',
          'humanIssues',
          'reportLanguage',
        });
        expect(payload['reportLanguage'], 'en');
      },
    );
  });
}

/// Every key path in a decoded JSON value, so two report renderings can be
/// compared for contract drift instead of by reading them side by side.
Set<String> _keyPaths(Object? node, [String prefix = '']) {
  if (node is Map) {
    return {
      for (final entry in node.entries) ...[
        '$prefix/${entry.key}',
        ..._keyPaths(entry.value, '$prefix/${entry.key}'),
      ],
    };
  }
  if (node is List) {
    return {
      for (var i = 0; i < node.length; i++)
        ..._keyPaths(node[i], '$prefix[$i]'),
    };
  }
  return const {};
}
