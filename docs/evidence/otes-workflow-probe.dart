import 'dart:convert';
import 'dart:io';
import '/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/lib/data/parsing/requirement_splitter.dart';

void main() {
  const source = '/Users/lehuytuong/Downloads/OTES_officially_document.docx.pdf';
  final extraction = Process.runSync('pdftotext', ['-layout', source, '-']);
  if (extraction.exitCode != 0) {
    stderr.write(extraction.stderr);
    exit(extraction.exitCode);
  }
  final pages = (extraction.stdout as String).split('\f');
  final srs = pages.sublist(22, 155);
  final header = RegExp(r'Use Case No\.\s*(UC\d+)', caseSensitive: false);
  final sourceIds = srs.expand((p) => header.allMatches(p).map((m) => m.group(1)!)).toList();
  const splitter = RequirementSplitter();
  final items = splitter.split(srs);
  final duplicateProbe = splitter.split([
    'UC04 View study schedule\nThe system shall display the schedule.',
    'UC04 Join classroom\nThe system shall connect the student to the classroom and acquire media streams.'
  ]);
  final numberedFlowProbe = splitter.split([
    'UC03 Take exam\nMain success scenario:\n1. Student enters answers.\n2. Student submits the exam.\nBusiness Rules:\nThe student must keep the camera on.'
  ]);
  final out = {
    'kind': 'diagnostic_baseline_not_new_pipeline_validation',
    'source': source,
    'scope_pdf_pages': [23, 155],
    'extraction': 'pdftotext -layout -> current Dart RequirementSplitter; NOT Syncfusion end-to-end',
    'source_use_case_headers': sourceIds.length,
    'source_literal_unique_ids': sourceIds.toSet().length,
    'source_numeric_unique_ids': sourceIds.map((s) => int.parse(s.substring(2))).toSet().length,
    'splitter_total_items': items.length,
    'splitter_use_case_items': items.where((i) => i.isUseCase).length,
    'splitter_uc_ids': items.where((i) => i.isUseCase).map((i) => i.id).toList(),
    'synthetic_duplicate': {
      'expected_occurrences': 2,
      'actual_occurrences': duplicateProbe.length,
      'preserves_both': duplicateProbe.length == 2,
      'kept_text': duplicateProbe.map((i) => i.text).toList(),
    },
    'synthetic_numbered_flow': {
      'preserves_submit_step': numberedFlowProbe.any((i) => i.isUseCase && i.text.contains('Student submits')),
      'items': numberedFlowProbe.map((i) => {'id': i.id, 'text': i.text}).toList(),
    },
  };
  final json = const JsonEncoder.withIndent('  ').convert(out);
  File('/tmp/otes-workflow-baseline.json').writeAsStringSync('$json\n');
  print(json);
  if (sourceIds.length != 63) {
    stderr.writeln('Source inventory changed; review baseline before interpreting probe.');
    exit(2);
  }
  if (duplicateProbe.length != 2 || !numberedFlowProbe.any((i) => i.isUseCase && i.text.contains('Student submits'))) {
    stderr.writeln('BASELINE FAIL: current splitter does not preserve duplicate occurrences and/or numbered flow.');
    exit(1);
  }
}
