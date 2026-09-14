@Timeout(Duration(minutes: 5))
library;
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/checks/text_fold.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

void main() {
  test('gate diagnostics: isCaptionIndex + intermediates per page', () async {
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(
          await File(Platform.environment['SRS_TEST_PDF']!).readAsBytes()),
      fileName: 'o.pdf');
    const c = DiagramTypeClassifier();
    for (final p in [6, 7, 9, 155, 156, 159, 160, 167, 170, 180, 181]) {
      final t = doc.pageTexts[p];
      final lines = const LineSplitter().convert(t);
      final firstFolded =
          lines.take(2).map((l) => foldVietnamese(l).trim()).toList();
      print('GATE|$p|index=${c.isCaptionIndex(t)}|nlines=${lines.length}');
      print('FOLD|$p|'
          '${firstFolded.map((e) => e.substring(0, e.length.clamp(0, 70))).join(" // ")}');
    }
  });
}
