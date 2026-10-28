@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';

// ignore_for_file: avoid_print
void main() {
  test('locate cited captions across all pages', () async {
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(
        await File(Platform.environment['SRS_TEST_PDF']!).readAsBytes(),
      ),
      fileName: 'otes.pdf',
    );
    for (final needle in [
      'Table 40',
      'Figure 62',
      'Figure 63',
      'Figure 61',
      'Save student',
      "student's video",
    ]) {
      final pages = <int>[];
      for (var i = 0; i < doc.pageTexts.length; i++) {
        if (doc.pageTexts[i].contains(needle)) pages.add(i);
      }
      print('WHERE|$needle|pages=$pages');
    }
  });
}
