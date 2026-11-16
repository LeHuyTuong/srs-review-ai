@Timeout(Duration(minutes: 5))
library;

// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';

void main() {
  test('per-candidate: named by REQ text or by PAGE text or by image', () async {
    final doc = await ParseService().parse(
      bytes: Uint8List.fromList(
        await File(Platform.environment['SRS_TEST_PDF']!).readAsBytes(),
      ),
      fileName: 'otes.pdf',
    );
    const c = DiagramTypeClassifier();
    final visual = doc.imagePageIndexes.toSet();
    final reqPages = <int>{};
    for (final item in doc.requirements) {
      if (item.pageIndex != null && item.pageIndex! >= 0) {
        if (c.classify(item.text) != DiagramKind.unknown) {
          reqPages.add(item.pageIndex!);
        }
      }
    }
    for (var p = 0; p < doc.pageTexts.length; p++) {
      final t = doc.pageTexts[p];
      if (t.isEmpty) continue;
      final byPage = c.classify(t) != DiagramKind.unknown;
      final byReq = reqPages.contains(p);
      final byImg = visual.contains(p);
      if (byPage || byReq || byImg) {
        print(
          'SRC|$p|page:${byPage ? c.classify(t).wire : 'na'}|req:$byReq|img:$byImg'
          '|index:${c.isCaptionIndex(t)}|tlen:${t.length}',
        );
      }
    }
  });
}
