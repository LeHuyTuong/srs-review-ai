// One-off probe against the real OTES. Questions it answers, in order:
// 1. What non-ASCII characters do the flagged requirement texts actually
//    contain (real Vietnamese letters vs typographic punctuation)?
// 2. Does page text carry Vietnamese diacritics at all (case-insensitive)?
// 3. What do the new QualityChecks report on the real document?
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/quality_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/checks/syllabus_checks.dart';
import 'package:srs_review_ai/data/checks/text_fold.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

String _hex(String s) =>
    'U+${s.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0')}';

void main() {
  test('probe real OTES text composition', () async {
    final path = Platform.environment['SRS_TEST_PDF'];
    if (path == null || !File(path).existsSync()) {
      markTestSkipped('SRS_TEST_PDF not set');
      return;
    }
    final bytes = Uint8List.fromList(await File(path).readAsBytes());
    final document = await ParseService().parse(
      fileName: 'OTES_officially_document.docx.pdf',
      bytes: bytes,
    );

    // 1. Codepoint census over requirement texts: letters-with-diacritics
    // vs punctuation, across ALL flagged items, not just the first.
    final letterChars = <String>{}; // >127 and a letter
    final punctChars = <String>{}; // >127 and not a letter
    for (final r in document.requirements) {
      for (final unit in r.text.split('')) {
        final code = unit.codeUnitAt(0);
        if (code <= 127) continue;
        if (RegExp('[\\p{L}]', unicode: true).hasMatch(unit)) {
          letterChars.add(unit);
        } else {
          punctChars.add(unit);
        }
      }
    }
    // ignore: avoid_print
    print(
      'CENSUS|letters=${letterChars.map(_hex).join(' ')}'
      '|punct=${punctChars.map(_hex).join(' ')}',
    );

    // 2. Case-insensitive Vietnamese control words in the full page text.
    final controls = {
      'he-thong': RegExp('he thong'),
      'nguoi-dung': RegExp('nguoi dung'),
      'nhanh-chong': RegExp('nhanh chong'),
      'vv': RegExp(r'\bv\.v\.', caseSensitive: false),
      'su-dung': RegExp('su dung'),
    };
    final counts = {for (final k in controls.keys) k: 0};
    for (final t in document.pageTexts) {
      final folded = foldVietnamese(t);
      for (final e in controls.entries) {
        counts[e.key] = counts[e.key]! + e.value.allMatches(folded).length;
      }
    }
    // ignore: avoid_print
    print('CONTROLS|$counts');

    // 3. New quality checks on the real document.
    final findings = const QualityChecks().run(document);
    final vague = findings
        .where((f) => f.check == CheckId.ambiguousWording && !f.passed)
        .toList();
    final tbd = findings
        .where((f) => f.check == CheckId.placeholderTbd && !f.passed)
        .toList();
    // ignore: avoid_print
    print('QUALITY|vague=${vague.length}|tbd=${tbd.length}');
    final langFail = <String>[];
    for (final r in document.requirements) {
      if (!LanguageDetector.looksEnglish(r.text)) langFail.add(r.id);
    }
    var shown = 0;
    for (final r in document.requirements) {
      if (!LanguageDetector.looksEnglish(r.text) && shown < 3) {
        shown++;
        final f = foldVietnamese(r.text).replaceAll('\n', ' ');
        // ignore: avoid_print
        print('FAILTEXT[${r.id}] = ${Uri.encodeComponent(f.length > 160 ? f.substring(0, 160) : f)}');
      }
    }
    // ignore: avoid_print
    print('LANGFAIL|count=${langFail.length}|first=${langFail.take(3).join(',')}');
    for (final r in document.requirements) {
      if (r.id == 'UC-01') {
        final f = foldVietnamese(r.text);
        print('UC01FOLDED|${Uri.encodeComponent(f.length > 300 ? f.substring(0, 300) : f)}');
        break;
      }
    }
    for (final r in document.requirements) {
      final idx = r.text.indexOf('\u0300');
      if (idx >= 0) {
        final around = r.text.substring((idx - 30).clamp(0, r.text.length),
            (idx + 30).clamp(0, r.text.length));
        // ignore: avoid_print
        print('COMBINING[${r.id}] = ${Uri.encodeComponent(around)}');
        break;
      }
    }
    for (final f in vague.take(5)) {
      // ignore: avoid_print
      print('VAGUE|${f.subject}|${f.message}');
    }
  });
}
