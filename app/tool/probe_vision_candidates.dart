// Offline probe: what does VisionReviewService.candidates() select on the
// real OTES, and what kinds does the classifier name? Run:
//   SRS_TEST_PDF=… flutter test tool/probe_vision_candidates.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/services/vision_review_service.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';

void main() {
  test('real-document candidate probe', () async {
    final path = Platform.environment['SRS_TEST_PDF'];
    if (path == null || !File(path).existsSync()) {
      markTestSkipped('set SRS_TEST_PDF');
      return;
    }
    final document = await ParseService().parse(bytes: Uint8List.fromList(await File(path).readAsBytes()), fileName: path.split('/').last);
    final svc = VisionReviewService(
      auditor: (_) async => throw StateError('probe: no audit'),
      renderPage: (_, __) async => 'AA==',
    );
    final candidates = svc.candidates(document);
    print('CANDIDATES|count=${candidates.length}');
    for (final c in candidates) {
      print('PAGE|${c.pageIndex}|${c.kind.name}|${c.contextText.length}');
    }
    final kinds = candidates.fold(<String, int>{}, (m, c) {
      m[c.kind.name] = (m[c.kind.name] ?? 0) + 1;
      return m;
    });
    print('KINDS|$kinds');
    expect(candidates, isNotEmpty);
  });
}
