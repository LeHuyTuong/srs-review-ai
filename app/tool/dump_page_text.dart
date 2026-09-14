@Timeout(Duration(minutes: 5))
library;
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

void main() {
  test('gate diagnostics: isCaptionIndex + intermediates per page', () async {
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(
          await File(Platform.environment['SRS_TEST_PDF']!).readAsBytes()),
      fileName: 'o.pdf');
    const c = DiagramTypeClassifier();
    for (final p in [4, 153, 168, 182, 183]) {
      final t = doc.pageTexts[p];
      final squished = t.replaceAll(RegExp(r'\s+'), ' ');
      print('CTX|$p|kind=${c.classify(t).name}|'
          '${squished.substring(0, squished.length.clamp(0, 160))}');
    }
  });
}
