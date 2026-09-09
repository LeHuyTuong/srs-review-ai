// Blast-radius probe: does the duplicate-ID merge corrupt the EXISTING
// deterministic syllabus checks (F7 count, F9 transactions)?
import 'dart:convert';
import 'dart:io';
import '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/lib/data/checks/rubric_config.dart';
import '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/lib/data/checks/syllabus_checks.dart';
import '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/lib/data/models/srs_document.dart';
import '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/lib/data/parsing/requirement_splitter.dart';

void main() {
  const rubricPath = '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/server/app/rubric.json';
  final rubric = RubricConfig.fromJson(
      jsonDecode(File(rubricPath).readAsStringSync()) as Map<String, dynamic>);
  final checks = SyllabusChecks(rubric);

  // A source with 8 UC tables whose code repeats (OTES: UC04 appears 8 times, pp.33-50).
  final pages = <String>[];
  for (var i = 1; i <= 8; i++) {
    pages.add('Use Case No. UC04\nTitle: variant $i\n'
        'Main success scenario:\n'
        '1. Actor does step one of variant $i.\n'
        '2. The system replies to step one.\n'
        '3. Actor does step two of variant $i.\n'
        '4. The system replies to step two.\n'
        '5. Actor confirms variant $i completion.\n'
        '6. The system records variant $i.');
  }
  final items = const RequirementSplitter().split(pages);
  final doc = SrsDocument(fileName: "probe", pageCount: pages.length, pageTexts: pages, requirements: items);
  final f7 = checks.useCaseCount(doc);
  final f9 = checks.useCaseSizes(doc);
  final out = {
    'kind': 'blast_radius_probe',
    'uc_tables_in_source': 8,
    'items_after_splitter': items.length,
    'F7_reported_actual': f7.actual,
    'F7_message': f7.message,
    'F9_findings': f9.map((f) => '${f.subject}: ${f.message}').toList(),
    'expected_if_units_preserved': '8 use cases, 6 transactions each',
  };
  print(const JsonEncoder.withIndent('  ').convert(out));
}
