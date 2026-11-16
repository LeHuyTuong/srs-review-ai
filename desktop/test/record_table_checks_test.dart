/// §G.3 (rulebook 1.8 LOCKED) — numbering inside bare-digit record tables.
///
/// The negative tests lead on purpose: the check reads RAW PAGE TEXT with a
/// heuristic detector (§G.1), so its main risk is firing where it should not
/// — an index, a one-row table, a single `No` column, footer noise. The
/// positives are synthetic on purpose: a duplicate pair and a gap are four
/// lines of text, no real document needed. The real HisWise dump runs last
/// and only when present, to prove the detector works on the actual text
/// layer (one cell per line, headers split across lines, tables spanning
/// pages) — not on my idealised fixture.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/record_table_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;

/// One table rendered the way the text layer prints it: one visual row per
/// line, header as separate lines (the real HisWise shape).
String _tablePage({
  required String title,
  required List<String> header,
  required List<List<String>> rows,
  String footer = 'Page | 7',
}) => [
  title,
  '',
  ...header,
  ...[for (final row in rows) ...row],
  footer,
].join('\n');

void main() {
  const checks = RecordTableChecks();

  // ------------------------------------------------------------- negative set

  group('§G.3 silence — regions that are NOT record tables', () {
    test('a unique table never fires', () {
      final page = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Authentication', 'Login', 'Allows students to log in.'],
          ['02', 'Authentication', 'Register', 'Allows guests to register.'],
        ],
      );
      expect(checks.recordTableNumbering([page]), isEmpty);
    });

    test('an index (header carries a Page column) stays silent', () {
      // List of Tables: id + caption + page — a pointer, not a record.
      final page = [
        'List of Tables',
        'Table',
        'Description',
        'Page',
        '1.1',
        'User table',
        '5',
        '1.2',
        'Folder table',
        '6',
      ].join('\n');
      expect(checks.recordTableNumbering([page]), isEmpty);
    });

    test('a single data row is a sentence, not an inventory', () {
      final page = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Authentication', 'Login', 'Allows students to log in.'],
        ],
      );
      expect(checks.recordTableNumbering([page]), isEmpty);
    });

    test('an id column without any description column stays silent', () {
      // Bare ids alone are just a numbered list.
      final page = ['References', 'No', '01', '02', '03'].join('\n');
      expect(checks.recordTableNumbering([page]), isEmpty);
    });

    test('footer-only lines and prose without an id header stay silent', () {
      expect(
        checks.recordTableNumbering([
          'Some prose section',
          'The system shall allow five concurrent users.',
          'Page | 7 Page | 8',
        ]),
        isEmpty,
      );
    });

    test('duplicate numbers in DIFFERENT tables are not a defect', () {
      // Two tables each starting at 01 is correct numbering; only the
      // number repeated WITHIN one table fires (per-table scope).
      final pageOne = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Auth', 'Login', 'Allows students to log in.'],
          ['02', 'Auth', 'Register', 'Allows guests to register.'],
        ],
        footer: 'Page | 7',
      );
      final pageTwo = _tablePage(
        title: '3. Code Packages',
        header: ['No', 'Package', 'Description'],
        rows: [
          ['01', 'Config', 'Configuration classes.'],
          ['02', 'Security', 'Authentication logic.'],
        ],
        footer: 'Page | 8',
      );
      expect(checks.recordTableNumbering([pageOne, pageTwo]), isEmpty);
    });
  });

  // ------------------------------------------------------------ positive set

  group('§G.3.1 duplicate row numbers (medium)', () {
    test('a repeated number inside one table fires once per number', () {
      final page = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Auth', 'Login', 'Allows students to log in.'],
          ['02', 'Auth', 'Register', 'Allows guests to register.'],
          ['02', 'Auth', 'Register', 'Allows guests to register again.'],
          ['03', 'Search', 'Search', 'Full-text search.'],
        ],
      );
      final findings = checks.recordTableNumbering([page]);
      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.check, CheckId.recordTableNumbering);
      expect(finding.severity, Severity.medium);
      expect(finding.passed, isFalse);
      expect(finding.messageEn, contains('"02"'));
      expect(finding.messageEn, contains('2 times'));
      expect(finding.messageVi, contains('"02"'));
      expect(finding.messageVi, contains('2 lần'));
    });

    test('two DIFFERENT repeated numbers fire twice', () {
      final page = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Auth', 'Login', 'Login flow.'],
          ['01', 'Auth', 'Sign in', 'Sign-in flow.'],
          ['02', 'Doc', 'Upload', 'Upload flow.'],
          ['02', 'Doc', 'Download', 'Download flow.'],
        ],
      );
      final findings = checks.recordTableNumbering([page]);
      expect(findings, hasLength(2));
      expect(findings.map((f) => f.severity), everyElement(Severity.medium));
    });
  });

  group('§G.3.2 numbering jumps (low)', () {
    test('a gap of two or more fires low and asks for eyeballing', () {
      final page = _tablePage(
        title: '4. Database Design',
        header: ['No', 'Table', 'Description'],
        rows: [
          ['1', 'User', 'User accounts.'],
          ['4', 'Folder', 'Folder records.'],
        ],
      );
      final findings = checks.recordTableNumbering([page]);
      expect(findings, hasLength(1));
      expect(findings.single.severity, Severity.low);
      expect(findings.single.messageEn, contains('"1"'));
      expect(findings.single.messageEn, contains('"4"'));
      expect(findings.single.messageVi, contains('kiểm tra bằng mắt'));
    });

    test('a reset (02 → 01) ends the run and stays silent', () {
      // The detector reads non-decreasing runs: a reset means the header
      // run restarts (or the extractor split the table). §G.3.2's message
      // covers the visible-jump case; a mid-page reset would produce two
      // runs, and neither is a duplicate nor a gap in itself.
      final page = _tablePage(
        title: '2. Use cases',
        header: ['ID', 'Feature', 'Use Case', 'Use Case Description'],
        rows: [
          ['01', 'Auth', 'Login', 'Login flow.'],
          ['02', 'Auth', 'Register', 'Register flow.'],
          ['01', 'Doc', 'Upload', 'Upload flow.'],
          ['02', 'Doc', 'Download', 'Download flow.'],
        ],
      );
      // 01→02 (run 1), 02→01 resets (run boundary), 01→02 again: no
      // duplicate within a run, no jump ≥ 2 — silence is the honest read.
      expect(checks.recordTableNumbering([page]), isEmpty);
    });
  });

  // ------------------------------------------- real HisWise dump (skip if absent)

  group('§G on the real HisWise extraction', () {
    test('recognises the UC and Package tables from the actual text layer', () {
      final tmp = Platform.environment['TEMP'] ?? 'C:/Temp';
      final input = File('$tmp/hiswise_pages.json');
      if (!input.existsSync()) {
        // ignore: avoid_print
        print('SKIP-G: khong co ${input.path}');
        return;
      }
      final pages =
          ((jsonDecode(input.readAsStringSync())
                      as Map<String, dynamic>)['pages']
                  as List<dynamic>)
              .cast<String>();

      final tables = checks.recordTables(pages);
      // MEASURED on the real dump (2026-09-29, not read off a spec): four
      // bare-digit record tables re-declare their header on their page —
      // use cases p7 (01–04), code packages p9 (01–05), package
      // descriptions p10 (01–03) and table descriptions p12 (1–2). The
      // continuation pages WITHOUT a repeated header (p8: 05–15, p10:
      // 06–14, p11: 04–14) are not table starts and stay out: per-page
      // fragment scope is the honest read for a per-table rule like
      // §G.3.1, and merging continuations across pages is heuristic
      // calibration that waits for the gold set (§G.4), like the parser
      // port. (An earlier draft of this comment claimed 3 tables of 14
      // rows — written from memory, wrong on both counts.)
      // ignore: avoid_print
      print(
        'G-PROBE: ${tables.length} bang / so hang: '
        '${tables.map((t) => t.numbers.length).join(",")}',
      );
      expect(tables.length, 4, reason: 'UC + Package + PkgDesc + TableDesc');
      expect(tables.map((t) => t.numbers.length).toList(), [4, 5, 3, 2]);
      expect(tables[0].numbers.first, '01');
      expect(tables[0].numbers.last, '04');
      expect(
        checks.recordTableNumbering(pages),
        isEmpty,
        reason: 'real HisWise numbering is clean',
      );
    });
  });
}
