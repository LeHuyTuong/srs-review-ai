/// One-off live batch: vision-audit the first 10 OTES diagram pages
/// through the running proxy, twice — run 2 proves cache economics and
/// ledger stability. Writes raw evidence to `/tmp/vision_batch_run1.json` (and run2).
///
///   SRS_TEST_PDF=… flutter test tool/vision_batch_run.dart
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/app_config.dart';
import 'package:srs_review_ai/diagram_audit/services/vision_review_service.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

void main() {
  test('live batch audit of real OTES pages', () async {
    final pdfPath = Platform.environment['SRS_TEST_PDF'];
    if (pdfPath == null || !File(pdfPath).existsSync()) {
      markTestSkipped('set SRS_TEST_PDF');
      return;
    }
    print('BASE|${AppConfig.apiBaseUrl}');
    final bytes = Uint8List.fromList(await File(pdfPath).readAsBytes());
    final document = await ParseService().parse(
      bytes: bytes,
      fileName: pdfPath.split('/').last,
    );
    // 10.0.2.2 is the *device's* alias for the host; a flutter test on the
    // host itself must dial 127.0.0.1 or every audit fails with a socket error.
    final api = ApiService(baseUrl: 'http://127.0.0.1:8000');
    final rawLog = <Map<String, dynamic>>[];

    final service = VisionReviewService(
      auditor: (request) async {
        final started = DateTime.now();
        final result = await api.diagramAudit(request);
        rawLog.add({
          'page': request.pageIndex,
          'kind': request.diagramType,
          'elapsedMs': DateTime.now().difference(started).inMilliseconds,
          'cached': result.cached,
          'elements': result.elements,
          'relations': [
            for (final r in result.relations)
              {'from': r.source, 'to': r.target, 'side': r.arrowheadSide},
          ],
          'unreadable': result.unreadable,
          'clean': result.clean,
          'findings': [
            for (final f in result.findings)
              {
                'family': f.family,
                'entity': f.entity,
                'evidence': f.evidence,
                'severity': f.severity,
              },
          ],
          'model': result.model,
        });
        return result;
      },
      // Rasterized on the host with poppler (217 pages → /tmp/otes_pages)
      // because the device renderer (pdfx = native pdfium over a platform
      // channel) cannot run inside flutter test at all. What is under
      // measurement here is the service→proxy chain; the renderer has its
      // own proven on-device path (the image-review QA run).
      renderPage: (pageIndex, _) async {
        final file = File(
          '/tmp/otes_pages/p-${(pageIndex + 1).toString().padLeft(3, '0')}.png',
        );
        if (!file.existsSync()) {
          throw StateError('no raster for page $pageIndex');
        }
        return base64Encode(await file.readAsBytes());
      },
    );

    final candidates = service.candidates(document);
    print('CANDIDATES|${candidates.length}');
    final run1 = await service.audit(document);
    for (final f in run1.findings) {
      print(
        'ROW1|${f.subject}|${f.passed}|${f.severity.name}|${f.messageEn.length}ch',
      );
    }
    print(
      'FAILURES1|${run1.failures.length}|${run1.skippedPages.length} skipped',
    );
    for (final f in run1.failures.take(3)) {
      print('FAIL1|$f');
    }
    File(
      '/tmp/vision_batch_run1.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rawLog));

    // Run 2: same pages — the server cache should answer instantly and the
    // ledger rows must be byte-identical (that is the stability contract).
    final rowsBefore = run1.findings
        .map((f) => '${f.subject}:${f.passed}:${f.severity}')
        .join('|');
    rawLog.clear();
    final run2 = await service.audit(document);
    final rowsAfter = run2.findings
        .map((f) => '${f.subject}:${f.passed}:${f.severity}')
        .join('|');
    final allCached =
        rawLog.isNotEmpty && rawLog.every((e) => e['cached'] == true);
    print('STABILITY|${rowsBefore == rowsAfter ? 'identical' : 'DRIFT'}');
    print('CACHE|all-run2-cached=$allCached');
    File(
      '/tmp/vision_batch_run2.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rawLog));
    expect(run1.findings, isNotEmpty);
  });
}
