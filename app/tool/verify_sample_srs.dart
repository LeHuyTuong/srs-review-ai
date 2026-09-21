@Timeout(Duration(minutes: 5))
library;

/// Verification probe (không phải unit test): đối chiếu finding của team review
/// với hành vi THẬT của parser + deterministic checks.
///
/// Chạy: flutter test tool/verify_sample_srs.dart -r expanded
/// Override file mẫu: SRS_SAMPLE_DOCX=/path/to/file.docx
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/blueprint_checks.dart';
import 'package:srs_review_ai/data/checks/diagram_detector.dart';
import 'package:srs_review_ai/data/checks/reference_checks.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/checks/syllabus_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/parsing/blueprint_builder.dart';
import 'package:srs_review_ai/data/parsing/table_of_contents.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

void _printFindings(String title, List<DeterministicFinding> findings) {
  print('--- $title (${findings.length}) ---');
  for (final f in findings) {
    print(
      '${f.passed ? 'PASS' : 'FAIL'} [${f.severity.name}] '
      '${f.check.name} | subject=${f.subject ?? '-'} | ${f.message}',
    );
  }
}

void main() {
  test('Part A: sample_srs.docx qua pipeline thật', () async {
    final path =
        Platform.environment['SRS_SAMPLE_DOCX'] ??
        '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/sample_srs.docx';
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(await File(path).readAsBytes()),
      fileName: path.split('/').last,
    );

    print('=== A1. DOCUMENT ===');
    print(
      'file=${doc.fileName} pages=${doc.pageCount} '
      'units=${doc.requirements.length} useCases=${doc.useCaseCount} '
      'imagePages=${doc.imagePageIndexes}',
    );

    print('=== A2. INVENTORY (units từ body-scan fallback) ===');
    for (final r in doc.requirements) {
      final preview = r.text.replaceAll(RegExp(r'\s+'), ' ');
      print(
        '${r.id} (${r.kind.name}, section=${r.section ?? '-'}, '
        'page=${r.pageIndex ?? '-'}) :: '
        '${preview.substring(0, preview.length.clamp(0, 90))}',
      );
    }

    print('=== A3. TOC trên DOCX (kỳ vọng: RỖNG → fallback body scan) ===');
    final toc = TableOfContents.parse(doc.pageTexts);
    print('toc.entries=${toc.entries.length} (isEmpty=${toc.isEmpty})');

    print('=== A4. DIAGRAM INTENT per unit (keyword scan hiện tại) ===');
    const detector = DiagramDetector();
    var hits = 0;
    for (final r in doc.requirements) {
      final s = detector.detect(r.text);
      if (s.mentionsDiagram) {
        hits++;
        print('${r.id}: matched="${s.matchedTerm}"');
      }
    }
    print('diagram-intent hits=$hits');

    final syllabus = const SyllabusChecks(RubricConfig.fallback).runAll(doc);
    _printFindings('A5. SYLLABUS + QUALITY (F7/F8/F9 + vague/TBD)', syllabus);

    final refs = const ReferenceChecks().runAll(doc);
    _printFindings('A6. REFERENCE (duplicateIds/postcondition/actor)', refs);
  });

  test('Part B: TOC fixture kiểu đồ án FPTU → lỗi bắt được với 0 token', () {
    // Giả lập 3 trang mục lục trích từ PDF (tab-leader shape như user paste).
    final pageTexts = <String>[
      'A.\tIntroduction\t11\n'
          'B.\tSoftware Project Management Plan\t14\n'
          'C.\tSoftware Requirement Specification\t22\n'
          'D.\tSoftware Design Description\t155\n'
          'E.\tSystem Implementation & Test\t182',
      'Table 9. <Unauthorized> Login\t25\n'
          'Table 22. USE CASE – Kick a student out of group\t54\n'
          'Table 23. USE CASE – Kick a student out of group\t56\n'
          'Table 40. USE CASE – Save student video\t91\n'
          'Table 42. USE CASE – Save student video\t95\n'
          'Table 43. USE CASE – Save student video\t96\n'
          'Table 48. USE CASE – Export Lecturer\t107\n'
          'Table 50. USE CASE – Export Lecturer\t111',
      'Figure 38. <Lecturer> View teaching schedule\t95\n'
          'Figure 39. <Lecturer> Join teaching classroom\t97\n'
          'Figure 41. <Admin> Get students\t100\n'
          'Figure 42. <Admin> Import students\t102\n'
          'Figure 75. Class Diagram\t160\n'
          'Figure 90. ERD Diagram\t180',
    ];

    final toc = TableOfContents.parse(pageTexts);
    print('=== B1. TOC PARSED ===');
    print(
      'entries=${toc.entries.length} '
      'chapters=${toc.entries.where((e) => e.kind == TocEntryKind.chapter).length} '
      'tables=${toc.tables.length} figures=${toc.figures.length} '
      'tocPages=${toc.pageIndexes}',
    );
    for (final e in toc.entries) {
      print('  $e');
    }

    // --- Mini BlueprintChecks (0 token) — demo giá trị DocumentBlueprint ---
    print('=== B2. BLUEPRINT CHECKS (0 token) ===');
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

    // Check 1: trùng caption (bỏ prefix 'use case' hay gặp trong LoT)
    final byCaption = <String, List<TocEntry>>{};
    for (final e in toc.tables) {
      final key = norm(e.title).replaceFirst(RegExp(r'^use case\s*'), '');
      byCaption.putIfAbsent(key, () => []).add(e);
    }
    var dupCount = 0;
    for (final entry in byCaption.entries) {
      if (entry.value.length > 1) {
        dupCount++;
        print(
          'FAIL [blueprint.duplicateCaption] "${entry.key}" x${entry.value.length}: '
          '${entry.value.map((e) => 'Table ${e.number} (tr ${e.page})').join(', ')}',
        );
      }
    }
    print('→ $dupCount cụm trùng tên Use Case phát hiện từ mục lục.');

    // Check 2: đứt số Figure/Table
    for (final kind in [TocEntryKind.figure, TocEntryKind.table]) {
      final nums =
          toc.entries
              .where((e) => e.kind == kind)
              .map((e) => e.number)
              .toList()
        ..sort();
      for (var i = 1; i < nums.length; i++) {
        if (nums[i] > nums[i - 1] + 1) {
          print(
            'FAIL [blueprint.numberingGap] ${kind.name}: nhảy từ '
            '${nums[i - 1]} → ${nums[i]} (thiếu ${nums[i - 1] + 1})',
          );
        }
      }
    }

    // Check 3: figure index → loại sơ đồ + trang đích cho vision
    print('=== B3. FIGURE INDEX → VISION TARGETING (thay heuristic) ===');
    const kindMap = {
      'class diagram': 'ClassDiagram',
      'sequence': 'SequenceDiagram',
      'activity': 'ActivityDiagram',
      'erd': 'ERD',
      'use case': 'UseCaseDiagram',
    };
    for (final f in toc.figures) {
      final title = f.title.toLowerCase();
      final kind = kindMap.entries
          .where((k) => title.contains(k.key))
          .map((k) => k.value)
          .firstOrNull;
      if (kind != null) {
        print('  Figure ${f.number} → $kind @ printedPage=${f.page}');
      }
    }
  });

  test('Part C: BlueprintBuilder + BlueprintChecks trên index thật', () {
    final pages = <String>[
      'A.\tIntroduction\t2\n'
          'B.\tSoftware Project Management Plan\t3\n'
          'C.\tSoftware Requirement Specification\t4\n'
          'D.\tSoftware Design Description\t6\n'
          'E.\tSystem Implementation & Test\t7',
      'Table 9. Unauthorized Login\t4\n'
          'Table 22. Use Case - Kick a student out of group\t5\n'
          'Table 23. Use Case - Kick a student out of group\t6\n'
          'Figure 39. Join teaching classroom\t6\n'
          'Figure 41. Get students\t7',
      'B. Software Project Management Plan',
      'C. Software Requirement Specification\n'
          'UC-01 The system shall let a student upload an SRS file.',
      'Table 9. Unauthorized Login',
      'D. Software Design Description\n'
          'Table 22. Use Case - Kick a student out of group\n'
          'Figure 39. Join teaching classroom',
      'E. System Implementation & Test\n'
          'Table 23. Use Case - Kick a student out of group\n'
          'Figure 41. Get students',
    ];

    final toc = TableOfContents.parse(pages);
    final blueprint = const BlueprintBuilder().build(
      pageTexts: pages,
      toc: toc,
    )!;

    print('=== C1. BLUEPRINT ===');
    print(blueprint);
    for (final section in blueprint.sections) {
      print('  section $section');
    }
    print('=== C2. ARTIFACTS ===');
    for (final artifact in blueprint.artifacts) {
      print('  $artifact → section=${artifact.sectionId}');
    }

    print('=== C3. BLUEPRINT FINDINGS (0 token) ===');
    final findings = const BlueprintChecks().runAll(blueprint);
    for (final finding in findings) {
      print(
        '${finding.passed ? 'PASS' : 'FAIL'} [${finding.severity.name}] '
        '${finding.check.wire} | ${finding.message}',
      );
    }
    print('→ ${findings.length} finding từ mục lục, chưa tốn token nào.');
  });
}
