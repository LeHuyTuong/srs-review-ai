// Dumps units for a host-extracted document so a batch driver can review it
// without a device.
//
// Why a harness instead of a script: the splitter IS the app's parser
// (RequirementSplitter, parser 1.4.4). Re-implementing it in Python to get
// HisWise units would produce a second parser that quietly disagrees with the
// first - the exact trap this repo keeps documenting. pdfx cannot help here: it
// is dead in every host test runner, so the page TEXT comes from PyMuPDF on the
// host and only the splitting runs in Dart.
//
// Input : %TEMP%\<name>_pages.json   {"source": ..., "pages": ["...", ...]}
// Output: %TEMP%\<name>_units.json    same shape as otes_units.json
//
// This is a dump, not an assertion: it must not fail the suite when the input
// file is absent, because a normal `flutter test` has no such file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/document_import/parsing/requirement_splitter.dart';

void main() {
  test('dumps units for a host-extracted document', () {
    final tmp = Platform.environment['TEMP'] ?? 'C:/Temp';
    final input = File('$tmp/hiswise_pages.json');
    if (!input.existsSync()) {
      // ignore: avoid_print
      print('BO QUA: khong co ${input.path}');
      return;
    }
    final doc = jsonDecode(input.readAsStringSync()) as Map<String, dynamic>;
    final pages = (doc['pages'] as List<dynamic>).cast<String>();

    final units = RequirementSplitter().split(pages);
    final out = {
      'source': doc['source'],
      'pages': pages.length,
      'units': [
        for (final u in units)
          {
            'requirement_id': u.id,
            'kind': u.kind.name,
            'text': u.text,
            'section': u.section,
            'page_index': u.pageIndex,
          },
      ],
    };
    File(
      '$tmp/hiswise_units.json',
    ).writeAsStringSync(jsonEncode(out), flush: true);
    // ignore: avoid_print
    print(
      'HISWISE: ${units.length} don vi / ${pages.length} trang '
      '(id: ${units.take(5).map((u) => u.id).join(",")}...)',
    );
  });
}
