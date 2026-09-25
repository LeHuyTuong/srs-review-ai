/// The Word (.docx) twin of the review report.
///
/// Added 2026-09-25 because "export to docs" was the one format a supervisor
/// actually opens, and the app could not produce it: markdown, JSON and HTML
/// existed, `.docx` did not. A .docx is a ZIP of OOXML parts, so this needs no
/// plugin and no renderer — `archive` writes the container, and the bytes go to
/// disk through the same `ReportExporter.save` the JSON/HTML twins use, which is
/// why it behaves identically on web (a browser download) and on
/// desktop/mobile (a save dialog).
///
/// It is a TWIN, not a fourth source of truth: the honesty contract comes from
/// [reportLimitations] and the rubric label from [kRubricLabel], exactly like
/// the markdown and HTML builders. A caveat added there lands here too.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/human_issue.dart';
import '../../../data/models/report_language.dart';
import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import 'report_export.dart';
import 'report_strings.dart';
import 'section_scores.dart';
import 'workspace_findings.dart';
import 'workspace_unit.dart';

/// Builds the .docx bytes for one report. Same inputs as [buildMarkdownReport]
/// and [buildHtmlReport], so the numbers cannot drift between the four exports.
Uint8List buildDocxReport({
  required String fileName,
  required bool offline,
  required WorkspaceReviewResult? result,
  required List<WorkspaceUnit> units,

  /// F7/F8/F9 and the other offline families. Rendered with their PASS/FAIL
  /// state, because a checklist row that silently omits the passing half is
  /// indistinguishable from a check that never ran.
  List<DeterministicFinding> syllabusFindings = const [],
  List<DeterministicFinding> referenceFindings = const [],
  List<DeterministicFinding> blueprintFindings = const [],

  int diagramPageCount = 0,
  bool imageReviewAvailable = false,
  int imageReviewedCount = 0,
  PageImageCoverage? imageCoverage,
  Map<String, FindingStatus> findingStatus = const {},
  List<HumanIssue> humanIssues = const [],

  /// The language the document is written in. See [buildMarkdownReport] for why
  /// the builder default stays English while the app passes the user's choice
  /// explicitly.
  ReportLanguage language = ReportLanguage.english,
}) {
  final s = ReportStrings(language);
  final reportOffline = result?.mock ?? offline;
  final findings = result?.findings ?? const <FindingRow>[];
  final scores = result?.scores ?? const <String, int>{};
  final average = scores.isEmpty
      ? '—'
      : (scores.values.reduce((a, b) => a + b) / scores.length).toStringAsFixed(
          2,
        );
  final high = findings.where((f) => f.severity == Severity.high).length;
  final medium = findings.where((f) => f.severity == Severity.medium).length;
  final low = findings.where((f) => f.severity == Severity.low).length;
  final effectiveReviewed = imageCoverage?.reviewed ?? imageReviewedCount;

  final body = <String>[];

  // ---------------------------------------------------------------- title
  body.add(
    _p(s.pick('SRS review report', 'Báo cáo đánh giá SRS'), style: 'Title'),
  );
  body.add(
    _p(
      '${fileName.trim().isEmpty ? s.pick('Untitled document', 'Tài liệu chưa đặt tên') : fileName} · '
      '${s.pick('generated', 'tạo lúc')} ${_stamp(DateTime.now().toUtc())}',
      style: 'Subtitle',
    ),
  );
  body.add(
    _p(
      '${s.pick('Rubric', 'Thang điểm')}: '
      '${rubricVersionLabel(result?.rubricVersion ?? kRubricLabel, s)} · '
      '${s.pick('language', 'ngôn ngữ')}: ${language.label} · '
      '${s.pick('mode', 'chế độ')}: '
      '${s.mode(reportOffline, short: true)}',
      style: 'Subtitle',
    ),
  );
  body.add(_p(s.languageNote, style: 'Subtitle'));
  if (imageCoverage?.rendererUnavailable ?? false) {
    // The same sentence the run summary and the Findings tab show. Without it
    // the report claims diagram coverage the run never had.
    body.add(
      _p(
        s.pick(
          'No PDF renderer on this platform — the diagrams were reviewed from text only.',
          'Nền tảng này không có bộ render PDF — sơ đồ chỉ được đánh giá từ văn bản.',
        ),
        bold: true,
      ),
    );
  }

  // -------------------------------------------------------- run summary
  body.add(
    _p(s.pick('1. Run summary', '1. Tóm tắt lượt chấm'), style: 'Heading1'),
  );
  body.add(
    _table(
      [
        [s.pick('Metric', 'Chỉ số'), s.pick('Value', 'Giá trị')],
        [
          s.pick('File', 'Tệp'),
          fileName.trim().isEmpty
              ? s.pick('Untitled document', 'Tài liệu chưa đặt tên')
              : fileName,
        ],
        [
          s.pick('Mode', 'Chế độ'),
          reportOffline
              ? s.pick('Offline mock', 'Mô phỏng ngoại tuyến')
              : s.pick('Online proxy', 'Trực tuyến qua proxy'),
        ],
        [s.pick('Model', 'Model'), result?.model ?? '—'],
        [
          s.pick('Rubric version', 'Phiên bản thang điểm'),
          result == null ? '—' : rubricVersionLabel(result.rubricVersion, s),
        ],
        [
          s.pick('Run outcome', 'Kết quả lượt chấm'),
          result?.outcome == null ? '—' : s.runOutcome(result!.outcome),
        ],
        [
          s.pick('Requirements reviewed', 'Số yêu cầu đã chấm'),
          '${result?.reviewed ?? 0}',
        ],
        [
          s.pick('Requirements skipped', 'Số yêu cầu bỏ qua'),
          '${result?.skipped ?? 0}',
        ],
        [
          s.pick('Requirements failed', 'Số yêu cầu lỗi'),
          '${result?.failed ?? 0}',
        ],
        [s.pick('Average score', 'Điểm trung bình'), average],
        [
          s.pick('Findings', 'Lỗi phát hiện'),
          '${findings.length} '
              '(${s.severityLabel(Severity.high).toLowerCase()} $high · '
              '${s.severityLabel(Severity.medium).toLowerCase()} $medium · '
              '${s.severityLabel(Severity.low).toLowerCase()} $low)',
        ],
        [
          s.pick(
            'Quotes dropped (not verbatim)',
            'Trích dẫn bị loại (không khớp nguyên văn)',
          ),
          '${result?.droppedIssueCount ?? 0}',
        ],
        [
          s.pick('Page images sent', 'Ảnh trang đã gửi'),
          imageReviewAvailable && !reportOffline
              ? s.pick(
                  '$effectiveReviewed requirement(s); $diagramPageCount diagram-like page(s) detected',
                  '$effectiveReviewed yêu cầu; phát hiện $diagramPageCount trang trông như có sơ đồ',
                )
              : s.pick(
                  'none (text-only run)',
                  'không có (lượt chấm chỉ văn bản)',
                ),
        ],
        [
          s.pick('Tokens', 'Token'),
          result == null
              ? '—'
              : '${result.totalTokens} (prompt ${result.promptTokens} · '
                    'completion ${result.completionTokens})',
        ],
      ],
      const [3000, 6638],
    ),
  );

  // ------------------------------------------------------ section scores
  final sections = summarizeSections(units: units, result: result);
  body.add(
    _p(
      s.pick('2. Scores by document section', '2. Điểm theo mục tài liệu'),
      style: 'Heading1',
    ),
  );
  if (sections.isEmpty) {
    body.add(
      _p(
        s.pick(
          'No scored sections in this run.',
          'Lượt chấm này không có mục nào được chấm điểm.',
        ),
      ),
    );
  } else {
    body.add(
      _table(
        [
          [
            s.pick('Section', 'Mục'),
            s.pick('Units', 'Số mục'),
            s.pick('Average', 'Trung bình'),
            s.pick('Findings', 'Lỗi'),
            s.pick('High', 'Nghiêm trọng'),
          ],
          for (final s in sections)
            [
              s.section,
              '${s.reviewedCount}',
              s.averageScore?.toStringAsFixed(2) ?? '—',
              '${s.findingCount}',
              '${s.highSeverityCount}',
            ],
        ],
        const [4438, 1000, 1400, 1400, 1400],
      ),
    );
  }

  // --------------------------------------------------- model findings
  body.add(
    _p(
      s.pick('3. Findings from the review model', '3. Lỗi do model phát hiện'),
      style: 'Heading1',
    ),
  );
  if (findings.isEmpty) {
    body.add(
      _p(
        s.pick(
          'The run produced no findings.',
          'Lượt chấm không phát hiện lỗi nào.',
        ),
      ),
    );
  } else {
    for (final f in findings) {
      final status = findingStatus[f.id] ?? FindingStatus.open;
      // The defect class is localized (it was printed as the raw enum name,
      // which put an English token in a Vietnamese finding line) and the
      // criterion the finding answers rides here too when the model named one.
      body.add(
        _p(
          '${f.id} · ${s.severityLabel(f.severity)} · '
          '${s.issueTypeLabel(f.issue.type)} · '
          '${s.pick('quote', 'trích dẫn')} '
          '${s.verificationLabel(f.issue.verification)}',
          style: 'Heading3',
        ),
      );
      body.add(
        _p(
          '${s.pick('Requirement', 'Yêu cầu')} ${f.requirementId} · '
          '${s.pick('page', 'trang')} ${f.pageIndex + 1} · '
          '${f.title} · ${s.pick('triage', 'phân loại')}: '
          '${s.findingStatusLabel(status)}'
          '${f.issue.criterionId == null || f.issue.criterionId!.isEmpty ? '' : ' · ${s.criterionRef(f.issue.criterionId!)}'}',
          style: 'Caption',
        ),
      );
      if (f.quote.trim().isNotEmpty) {
        body.add(_p(f.quote, style: 'Quote'));
      } else {
        body.add(
          _p(
            s.pick(
              '(the model returned no quote for this issue)',
              '(model không trả về trích dẫn cho lỗi này)',
            ),
            italic: true,
          ),
        );
      }
      if (f.suggestion.trim().isNotEmpty) {
        body.add(_p('${s.pick('How to fix', 'Cách sửa')}: ${f.suggestion}'));
      }
    }
  }

  // ------------------------------------------------ offline check layer
  // Not named `offline`: that is the bool parameter, and a local may not
  // shadow it — the collection below resolved to the bool and every
  // `.entries` in the loop became a getter on a bool.
  final offlineFamilies = <String, List<DeterministicFinding>>{
    s.pick('Syllabus thresholds (F7–F9)', 'Ngưỡng syllabus (F7–F9)'):
        syllabusFindings,
    s.pick('Consistency smells', 'Mùi nhất quán'): referenceFindings,
    s.pick('Document index and format', 'Mục lục và định dạng'):
        blueprintFindings,
  };
  body.add(
    _p(
      s.pick(
        '4. Offline checks (no model calls)',
        '4. Kiểm tra ngoại tuyến (không gọi model)',
      ),
      style: 'Heading1',
    ),
  );
  body.add(
    _p(
      s.pick(
        'These rows come from the rule-based layer: zero tokens, and the same evidence whether or not the network was reachable. "FAIL" is the row a student has to act on; "PASS" is shown so an absent check cannot be mistaken for a check that never ran.',
        'Các dòng này đến từ tầng luật: không tốn token, và bằng chứng như nhau dù có mạng hay không. Dòng "KHÔNG ĐẠT" là việc sinh viên phải xử lý; dòng "ĐẠT" được in ra để một kiểm tra vắng mặt không bị tưởng nhầm là kiểm tra chưa từng chạy.',
      ),
    ),
  );
  for (final entry in offlineFamilies.entries) {
    final rows = entry.value;
    body.add(
      _p(
        '${entry.key} — ${rows.length} ${s.pick('row(s)', 'dòng')}',
        style: 'Heading2',
      ),
    );
    if (rows.isEmpty) {
      body.add(
        _p(
          s.pick('Not run for this document.', 'Không chạy cho tài liệu này.'),
        ),
      );
      continue;
    }
    body.add(
      _table(
        [
          [
            s.pick('Criterion', 'Tiêu chí'),
            s.pick('Result', 'Kết quả'),
            s.pick('Severity', 'Mức độ'),
            s.pick('Subject', 'Đối tượng'),
            s.pick('Detail', 'Chi tiết'),
          ],
          for (final row in rows)
            [
              s.checkLabel(row.check),
              row.passed ? s.pick('PASS', 'ĐẠT') : s.pick('FAIL', 'KHÔNG ĐẠT'),
              row.passed ? '—' : s.severityLabel(row.severity),
              row.subject ?? '—',
              _evidence(row, s),
            ],
        ],
        const [3000, 900, 1000, 1500, 3238],
      ),
    );
  }

  // ------------------------------------------------ reviewer-authored
  body.add(
    _p(
      s.pick(
        '5. Issues recorded by the reviewer',
        '5. Lỗi do người review ghi',
      ),
      style: 'Heading1',
    ),
  );
  if (humanIssues.isEmpty) {
    body.add(
      _p(
        s.pick(
          'No reviewer-issued issues.',
          'Không có lỗi nào do người review ghi.',
        ),
      ),
    );
  } else {
    body.add(
      _table(
        [
          [
            s.pick('Severity', 'Mức độ'),
            s.pick('Section', 'Vị trí'),
            s.pick('Title', 'Tiêu đề'),
            s.pick('Detail', 'Chi tiết'),
            s.pick('Recorded', 'Thời điểm ghi'),
          ],
          for (final issue in humanIssues)
            [
              s.severityLabel(issue.severity),
              issue.section ?? '—',
              issue.title,
              issue.detail.trim().isEmpty ? '—' : issue.detail,
              _stamp(issue.createdAt),
            ],
        ],
        const [900, 1400, 2600, 3338, 1400],
      ),
    );
  }

  // ------------------------------------------------------------ inventory
  body.add(
    _p(
      s.pick('6. Document inventory', '6. Danh mục tài liệu'),
      style: 'Heading1',
    ),
  );
  body.add(
    _p(
      s.pick(
        'Every unit the parser produced, in document order — the scope this report is about, including the units that were not reviewed.',
        'Mọi mục bộ tách tạo ra, theo thứ tự tài liệu — đúng phạm vi báo cáo này nói tới, kể cả những mục chưa được chấm.',
      ),
    ),
  );
  if (units.isEmpty) {
    body.add(_p(s.pick('The inventory is empty.', 'Danh mục trống.')));
  } else {
    body.add(
      _table(
        [
          [
            s.pick('ID', 'Mã'),
            s.pick('Kind', 'Loại'),
            s.pick('Section', 'Mục'),
            s.pick('Page', 'Trang'),
            s.pick('Status', 'Trạng thái'),
            s.pick('Selected', 'Được chọn'),
          ],
          for (final u in units)
            [
              u.id,
              s.unitKindLabel(u.kind),
              u.section ?? '—',
              '${u.pageIndex + 1}',
              s.unitStatusLabel(u.status.name),
              s.yesNo(u.selected),
            ],
        ],
        const [1400, 1400, 2600, 700, 1500, 2038],
      ),
    );
  }

  // ---------------------------------------------------------- limitations
  body.add(
    _p(
      s.pick(
        '7. Limitations and evidence notes',
        '7. Giới hạn và ghi chú bằng chứng',
      ),
      style: 'Heading1',
    ),
  );
  body.add(
    _p(
      s.pick(
        'This section is not optional. A reader who only sees the score above cannot tell which of these caveats applied to their run.',
        'Mục này không được bỏ. Người chỉ đọc phần điểm ở trên không thể biết điều nào trong các lưu ý này áp dụng cho lượt chấm của mình.',
      ),
    ),
  );
  for (final line in reportLimitations(
    offline: reportOffline,
    language: language,
  )) {
    body.add(_p('• $line', indentLeft: 360));
  }

  return _package(
    body.join(),
    s.pick('SRS review report', 'Báo cáo đánh giá SRS'),
  );
}

/// `YYYY-MM-DD HH:mm` in UTC. The report is a record of a run, so it states the
/// clock it was produced on rather than a local time that changes meaning on
/// the reader's machine.
String _stamp(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}';
}

/// The one cell that says *why* a check fired, numbers included: "actual 12" is
/// the difference between a finding a student can act on and a slogan.
String _evidence(DeterministicFinding row, ReportStrings s) {
  final text = StringBuffer(row.messageFor(s.language));
  final numbers = <String>[];
  if (row.actual != null) {
    numbers.add('${s.pick('actual', 'thực tế')} ${row.actual}');
  }
  if (row.expectedMin != null) {
    numbers.add('${s.pick('min', 'tối thiểu')} ${row.expectedMin}');
  }
  if (row.expectedMax != null) {
    numbers.add('${s.pick('max', 'tối đa')} ${row.expectedMax}');
  }
  if (numbers.isNotEmpty) text.write(' (${numbers.join(' · ')})');
  if (row.requiresVisionEvidence) {
    text.write(
      ' [${s.pick('needs diagram evidence', 'cần bằng chứng sơ đồ')}]',
    );
  }
  return text.toString();
}

/// XML-escapes text AND drops the control characters a PDF text layer really
/// does contain. Word refuses to open a part holding e.g. `0x0B`, so this is
/// not defensive padding — it is the difference between a file that opens and
/// one that does not.
String _esc(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _rPr({bool bold = false, bool italic = false, String? color}) {
  final b = StringBuffer();
  if (bold) b.write('<w:b/>');
  if (italic) b.write('<w:i/>');
  if (color != null) b.write('<w:color w:val="$color"/>');
  return b.isEmpty ? '' : '<w:rPr>$b</w:rPr>';
}

/// One run per line, because extracted requirement text is multi-line and a
/// `w:t` newline is silently collapsed by Word.
String _run(
  String text, {
  bool bold = false,
  bool italic = false,
  String? color,
}) {
  final props = _rPr(bold: bold, italic: italic, color: color);
  final lines = text.split('\n');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) out.add('<w:r><w:br/></w:r>');
    out.add(
      '<w:r>$props<w:t xml:space="preserve">${_esc(lines[i])}</w:t></w:r>',
    );
  }
  return out.join();
}

String _p(
  String text, {
  String style = 'Normal',
  bool bold = false,
  bool italic = false,
  String? color,
  int? indentLeft,
}) {
  final props = StringBuffer('<w:pPr><w:pStyle w:val="$style"/>');
  if (indentLeft != null) props.write('<w:ind w:left="$indentLeft"/>');
  props.write('</w:pPr>');
  return '<w:p>$props${_run(text, bold: bold, italic: italic, color: color)}</w:p>';
}

/// A bordered table with a shaded header row. The trailing empty paragraph is
/// required, not cosmetic: Word merges two tables that touch, and a table as the
/// last block of a document is invalid.
///
/// Every `widths` list sums to 9638 twips — the A4 text width inside the 2cm
/// margins of [sectPr]. Word scales a `pct` table to the text column, so the sum
/// is what keeps a six-column inventory legible instead of one narrow column
/// beside five collapsed ones.
String _table(List<List<String>> rows, List<int> widths) {
  const border =
      '<w:top w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="B9C4BE"/>';
  final out = StringBuffer()
    ..write(
      '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>'
      '<w:tblLayout w:type="fixed"/><w:tblBorders>$border</w:tblBorders>'
      '</w:tblPr><w:tblGrid>',
    );
  for (final w in widths) {
    out.write('<w:gridCol w:w="$w"/>');
  }
  out.write('</w:tblGrid>');
  for (var r = 0; r < rows.length; r++) {
    final header = r == 0;
    out.write('<w:tr>');
    for (var c = 0; c < widths.length; c++) {
      final cell = c < rows[r].length ? rows[r][c] : '';
      out
        ..write(
          '<w:tc><w:tcPr><w:tcW w:w="${widths[c]}" w:type="dxa"/>'
          '${header ? '<w:shd w:val="clear" w:color="auto" w:fill="EEF3F0"/>' : ''}'
          '</w:tcPr>',
        )
        ..write(_p(cell, bold: header))
        ..write('</w:tc>');
    }
    out.write('</w:tr>');
  }
  out
    ..write('</w:tbl>')
    ..write(_p(''));
  return out.toString();
}

/// A4 portrait, 2cm margins — the size a capstone report is printed at, so the
/// exported file needs no re-formatting before it is attached to a submission.
const String _sectPr =
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
    'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>';

const String _xmlHeader =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

const String _wNs =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

const String _pkgNs =
    'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';

/// Only the styles the report actually uses. `Quote` is the one that carries
/// meaning: the verbatim sentence a student must find in their own document,
/// indented and italic so it can never be read as the reviewer's own words.
const String _styles =
    '''
$_xmlHeader
<w:styles $_wNs>
  <w:docDefaults>
    <w:rPrDefault><w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
      <w:sz w:val="22"/><w:szCs w:val="22"/>
    </w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/><w:qFormat/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:spacing w:before="0" w:after="80"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="44"/><w:szCs w:val="44"/><w:color w:val="1F3B2C"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/><w:color w:val="5A6B62"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="320" w:after="120"/>
      <w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="30"/><w:szCs w:val="30"/><w:color w:val="1F3B2C"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/>
      <w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="35543F"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/>
      <w:outlineLvl w:val="2"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Caption">
    <w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:rPr><w:i/><w:sz w:val="18"/><w:szCs w:val="18"/><w:color w:val="5A6B62"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Quote">
    <w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:ind w:left="360"/><w:spacing w:before="60" w:after="120"/>
      <w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="7E9B8A"/></w:pBdr>
    </w:pPr>
    <w:rPr><w:i/></w:rPr>
  </w:style>
</w:styles>''';

const String _contentTypes =
    '''
$_xmlHeader
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

const String _rootRels =
    '''
$_xmlHeader
<Relationships $_pkgNs>
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

const String _documentRels =
    '''
$_xmlHeader
<Relationships $_pkgNs>
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

/// The document properties Word shows in its title bar and File → Info pane.
/// They follow the report language: a Vietnamese .docx that introduces itself
/// as "SRS review report" in the window title is the same half-and-half the
/// rest of this file removes.
String _coreProps(String title) =>
    '''
$_xmlHeader
<cp:coreProperties
  xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>$title</dc:title>
  <dc:creator>SRS Review AI</dc:creator>
  <cp:lastModifiedBy>SRS Review AI</cp:lastModifiedBy>
</cp:coreProperties>''';

const String _appProps =
    '''
$_xmlHeader
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>SRS Review AI</Application>
</Properties>''';

/// Zips the parts. Part ORDER matters to strict readers: `[Content_Types].xml`
/// must be the first entry in an OPC package, which is why it is added first
/// rather than alongside the rest.
Uint8List _package(String body, String title) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(ArchiveFile.string('docProps/core.xml', _coreProps(title)))
    ..addFile(ArchiveFile.string('docProps/app.xml', _appProps))
    ..addFile(
      ArchiveFile.string(
        'word/document.xml',
        '$_xmlHeader<w:document $_wNs><w:body>$body$_sectPr</w:body></w:document>',
      ),
    )
    ..addFile(ArchiveFile.string('word/styles.xml', _styles))
    ..addFile(
      ArchiveFile.string('word/_rels/document.xml.rels', _documentRels),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
