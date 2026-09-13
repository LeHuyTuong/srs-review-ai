/// Showcase harness — renders ALL THREE report twins over the real OTES
/// document, zero LLM tokens (deterministic floor only), and asserts the
/// cross-twin parity the R32 audit series established.
///
/// Run (the PDF stays local; outputs go to /tmp/otes-showcase/):
///   OTES_PDF=/path/to.pdf flutter test tool/otes_report_showcase.dart
///
/// Like the M0 manifest, this is a `flutter test` file on purpose:
/// syncfusion_flutter_pdf needs the test VM's bindings but not a desktop
/// build. Skips without the file, so CI never depends on a 28.7 MB input.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/contradiction_pass.dart';
import 'package:srs_review_ai/data/checks/reference_checks.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/checks/syllabus_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';
import 'package:srs_review_ai/features/workspace/models/html_report.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';

final String _sourcePath =
    Platform.environment['OTES_PDF'] ??
    '${Platform.environment['HOME']}/Downloads/OTES_officially_document.docx.pdf';

const String _outDir = '/tmp/otes-showcase';

void _record(String event, Map<String, Object?> data) {
  // ignore: avoid_print
  print('SHOWCASE|$event|${jsonEncode(data)}');
}

void main() {
  final path = _sourcePath;
  final present = File(path).existsSync();

  test(
    'three report twins over real OTES, parity + ID stability',
    () async {
      final bytes = Uint8List.fromList(await File(path).readAsBytes());
      final document = await ParseService().parse(
        fileName: 'OTES_officially_document.docx.pdf',
        bytes: bytes,
      );
      final units = unitsFromDocument(document);
      final syllabus = SyllabusChecks(RubricConfig.fallback).runAll(document);
      // Mirror the production composition exactly (document_repository):
      // reference family = ReferenceChecks + ContradictionPass. Order is
      // already deterministic — the checks emit in stable sequence, which
      // is what the ID-stability assertion below measures.
      final reference = [
        ...const ReferenceChecks().runAll(document),
        ...const ContradictionPass().detect(document),
      ];
      final syllabusFindings = syllabus;
      final referenceFindings = reference;

      String renderMarkdown() => buildMarkdownReport(
        fileName: 'OTES_officially_document.docx.pdf',
        offline: true,
        result: null,
        units: units,
        syllabusFindings: syllabusFindings,
        referenceFindings: referenceFindings,
      );
      String renderJson() => const JsonEncoder.withIndent('  ').convert(
        buildJsonReport(
          fileName: 'OTES_officially_document.docx.pdf',
          offline: true,
          result: null,
          units: units,
          syllabusFindings: syllabusFindings,
          referenceFindings: referenceFindings,
        ),
      );
      String renderHtml() => buildHtmlReport(
        fileName: 'OTES_officially_document.docx.pdf',
        offline: true,
        result: null,
        units: units,
        syllabusFindings: syllabusFindings,
        referenceFindings: referenceFindings,
      );

      final md = renderMarkdown();
      final json = renderJson();
      final html = renderHtml();

      // ── Parity: the numbers every twin prints come from one source ────
      final total = syllabusFindings.length + referenceFindings.length;
      final payload = jsonDecode(json) as Map<String, dynamic>;
      final checks = (payload['deterministic_checks'] as List<dynamic>).cast<
        Map<String, dynamic>
      >();
      expect(checks, hasLength(total));
      expect(md, contains('Deterministic checks ($total)'));
      expect(html, contains('Deterministic checks ($total)'));
      // M2 family must appear in all three twins (R32 audit regression).
      expect(
        checks.where((c) => c['family'] == 'reference'),
        hasLength(referenceFindings.length),
      );
      expect(md, contains('reference (M2)'));
      expect(html, contains('reference (M2)'));

      // The OTES headline pattern must be visible in every artefact: use
      // cases with no Postcondition. Anchor on the real finding message
      // rather than a guessed wording — if the copy changes, the check
      // still measures visibility.
      final missingPostRows = referenceFindings
          .where((f) => f.check == CheckId.missingPostcondition && !f.passed)
          .toList(growable: false);
      expect(missingPostRows, isNotEmpty);
      final anchorRaw = missingPostRows.first.message;
      // Each twin escapes the way it renders: markdown pipes, HTML entities.
      final mdAnchor = anchorRaw.replaceAll('|', '\\|');
      final htmlAnchor = anchorRaw
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
      _record('counts', {
        'pages': document.pageCount,
        'units': units.length,
        'syllabus': syllabusFindings.length,
        'reference': referenceFindings.length,
        'missingPostcondition': missingPostRows.length,
      });
      expect(md, contains(mdAnchor), reason: 'M2 headline invisible in markdown');
      expect(
        html,
        contains(htmlAnchor),
        reason: 'M2 headline invisible in the HTML dashboard',
      );

      // ── Ledger stability: same inputs, byte-identical twins apart from
      // the generation timestamp. This is the R9/R14/R16 gate extended to
      // every export format — a re-run must not renumber or reshuffle.
      String withoutTimestamps(String text) => text
          .replaceAll(
            RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[.\d]*Z?'),
            'TS',
          )
          .replaceAll(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC'), 'TS');
      expect(
        withoutTimestamps(renderMarkdown()),
        withoutTimestamps(md),
        reason: 'markdown twin not reproducible',
      );
      expect(
        withoutTimestamps(renderJson()),
        withoutTimestamps(json),
        reason: 'JSON twin not reproducible',
      );
      expect(
        withoutTimestamps(renderHtml()),
        withoutTimestamps(html),
        reason: 'HTML twin not reproducible',
      );

      // ── Emit the showcase artefacts ───────────────────────────────────
      final dir = Directory(_outDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      File('$_outDir/ledger.md').writeAsStringSync(md);
      File('$_outDir/ledger.json').writeAsStringSync(json);
      final htmlPath = '$_outDir/ledger.html';
      File(htmlPath).writeAsStringSync(html);
      _record('written', {
        'dir': _outDir,
        'htmlBytes': File(htmlPath).lengthSync(),
        'mdBytes': File('$_outDir/ledger.md').lengthSync(),
      });
    },
    skip: present ? false : 'no real OTES at $path (set OTES_PDF=…)',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
