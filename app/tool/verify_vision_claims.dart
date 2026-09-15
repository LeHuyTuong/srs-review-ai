@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

// ignore_for_file: avoid_print
void main() {
  test('cross-check vision claims against page text', () async {
    final path = Platform.environment['SRS_TEST_PDF']!;
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(await File(path).readAsBytes()),
      fileName: 'otes.pdf',
    );
    String page(int i) =>
        i < doc.pageTexts.length ? doc.pageTexts[i] : '<none>';
    print(
      'P6 Table40:${page(6).contains('Table 40')} Table42:${page(6).contains('Table 42')} Table43:${page(6).contains('Table 43')}',
    );
    print(
      'P6 SaveVideo:${page(6).toLowerCase().contains("save student") || page(6).contains('video')}',
    );
    print(
      'P9 Figure62:${page(9).contains('Figure 62')} Figure63:${page(9).contains('Figure 63')} Figure61:${page(9).contains('Figure 61')}',
    );
    final p9 = page(9);
    final figIdx = RegExp(
      r'Figure \d+',
    ).allMatches(p9).map((m) => m.group(0)).take(20).join(', ');
    print('P9 figures: $figIdx');
    print(
      'P159 ExamComp:${page(159).contains('Exam')} Router:${page(159).contains('Router')}',
    );
    print(
      'P160 arrowhead-less claim needs image; text has: ClassStudent:${page(160).contains('ClassStudent')} Schedule:${page(160).contains('Schedule')}',
    );
  });
}
