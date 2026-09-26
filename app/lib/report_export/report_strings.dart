/// Every string the report builders need that is not already bilingual on the
/// finding itself, chosen by the language the user picked.
///
/// Why [pick] and not a lookup table: the two languages sit next to each other
/// at the point of use, so a builder gaining an English literal is visible as a
/// missing Vietnamese argument in the diff. The failure this guards against is
/// silent — a report that is 90% one language is worse than one that admits it
/// is bilingual, and nothing in a compiler flags a Spanish literal.
///
/// What is deliberately NOT in here: the document's own text (unit titles,
/// section headings, quotes) and anything a human typed. Those are evidence,
/// and evidence is quoted, not translated.
library;

import '../deterministic_checks/models/deterministic_finding.dart';
import '../document_import/models/workspace_unit.dart';
import '../requirement_review/models/document_verdict.dart';
import '../requirement_review/models/finding_status.dart';
import '../requirement_review/models/report_language.dart';
import '../requirement_review/models/review_models.dart'
    show IssueType, Severity, Verification;

class ReportStrings {
  const ReportStrings(this.language);

  final ReportLanguage language;

  bool get isVietnamese => language == ReportLanguage.vietnamese;

  /// Both renderings, next to each other, at the point of use.
  String pick(String en, String vi) => isVietnamese ? vi : en;

  /// `CheckId` label. The enum's own `label` is English and is what the report
  /// printed before this switch existed; the Vietnamese column is new.
  String checkLabel(CheckId check) => switch (check) {
    CheckId.ucCount => pick('Use case count', 'Số lượng Use Case'),
    CheckId.language => pick('English only', 'Chỉ dùng tiếng Anh'),
    CheckId.ucSize => pick('Use case size', 'Kích thước Use Case'),
    CheckId.duplicateIds => pick(
      'Duplicate requirement ids',
      'Mã yêu cầu trùng',
    ),
    CheckId.missingPostcondition => pick(
      'Missing postcondition',
      'Thiếu hậu điều kiện',
    ),
    CheckId.crossArtifactName => pick(
      'Cross-artifact entity naming',
      'Tên thực thể không nhất quán',
    ),
    CheckId.missingActor => pick('Missing actor', 'Thiếu actor'),
    CheckId.ambiguousWording => pick('Vague wording', 'Câu chữ mơ hồ'),
    CheckId.placeholderTbd => pick('TBD / placeholder', 'TBD / chỗ trống'),
    CheckId.missingPriority => pick('Priority field', 'Trường độ ưu tiên'),
    CheckId.diagramAudit => pick('Diagram audit', 'Chấm sơ đồ'),
    CheckId.nfrUnquantified => pick(
      'Unquantified NFR',
      'NFR không có ngưỡng đo',
    ),
    CheckId.duplicateCaption => pick(
      'Duplicate caption in index',
      'Trùng tên bảng/hình trong mục lục',
    ),
    CheckId.numberingGap => pick(
      'Index numbering gap',
      'Nhảy số trong mục lục',
    ),
    CheckId.missingSection => pick(
      'Missing report part',
      'Thiếu phần bắt buộc',
    ),
    CheckId.unclassifiedFigure => pick(
      'Unclassified figure',
      'Hình không rõ loại sơ đồ',
    ),
    CheckId.captionPageMismatch => pick(
      'Index page out of date',
      'Mục lục sai trang',
    ),
    CheckId.coverPageInfo => pick('Cover page info', 'Thông tin trang bìa'),
    CheckId.headerFooterConsistency => pick(
      'Header/footer consistency',
      'Header/footer không nhất quán',
    ),
    CheckId.projectInfoMismatch => pick(
      'Declared info vs cover',
      'Khai báo vs trang bìa',
    ),
    CheckId.sectionOrder => pick('Chapter order', 'Thứ tự chương'),
    CheckId.headingNumbering => pick('Heading numbering', 'Đánh số heading'),
    CheckId.pageNumbering => pick('Page numbering', 'Đánh số trang'),
    CheckId.tablePositionDrift => pick(
      'Artifact moved from index page',
      'Bảng/hình bị dời khỏi trang mục lục',
    ),
  };

  /// `UnitKind` label for the inventory table.
  String unitKindLabel(UnitKind kind) => switch (kind) {
    UnitKind.useCase => pick('Use case', 'Use case'),
    UnitKind.businessRule => pick('Business rule', 'Quy tắc nghiệp vụ'),
    UnitKind.nonFunctional => pick('Non-functional', 'Phi chức năng'),
    UnitKind.functional => pick('Functional', 'Chức năng'),
    UnitKind.section => pick('Section', 'Mục văn bản'),
    UnitKind.unknown => pick('Unknown', 'Chưa phân loại'),
  };

  String findingStatusLabel(FindingStatus status) => switch (status) {
    FindingStatus.open => pick('Open', 'Chưa xử lý'),
    FindingStatus.fixed => pick('Fixed', 'Đã sửa'),
    FindingStatus.verified => pick('Verified', 'Đã xác minh'),
    FindingStatus.pendingVision => pick(
      'Pending vision',
      'Chờ kiểm tra hình ảnh',
    ),
    FindingStatus.disputed => pick('Disputed', 'Phản hồi là sai'),
  };

  /// The AI issue's defect class. `FindingRow.typeLabel` is the raw enum name
  /// (English, one word) and used to be printed as-is in the .docx, which put an
  /// English token in an otherwise Vietnamese finding line.
  String issueTypeLabel(IssueType type) => switch (type) {
    IssueType.ambiguity => pick('Ambiguity', 'Mơ hồ'),
    IssueType.vagueness => pick('Vagueness', 'Thiếu rõ ràng'),
    IssueType.untestable => pick('Untestable', 'Không thể kiểm thử'),
    IssueType.incomplete => pick('Incomplete', 'Chưa đầy đủ'),
    IssueType.inconsistent => pick('Inconsistent', 'Không nhất quán'),
    IssueType.duplicate => pick('Duplicate', 'Trùng lặp'),
    IssueType.other => pick('Other', 'Khác'),
  };

  /// How a finding names the criterion it answers (`criterion_id` on the wire).
  /// Only the word around it is translated: the id is the key of an editable
  /// row and the exact string a reader types back into the criteria list.
  String criterionRef(String id) => pick('criterion: $id', 'tiêu chí: $id');

  String severityLabel(Severity severity) => switch (severity) {
    Severity.low => pick('Low', 'Nhẹ'),
    Severity.medium => pick('Medium', 'Trung bình'),
    Severity.high => pick('High', 'Nghiêm trọng'),
  };

  /// How an AI finding's quote was matched against the document. Both values
  /// are facts about the evidence, so both are named out loud rather than left
  /// as the wire token.
  String verificationLabel(Verification verification) => switch (verification) {
    Verification.exact => pick('exact match', 'khớp nguyên văn'),
    Verification.fuzzy => pick('fuzzy match', 'khớp gần đúng'),
  };

  /// `UnitStatus` has no label of its own — the inventory used to print the
  /// raw `.name`, which is neither language.
  String unitStatusLabel(String status) => switch (status) {
    'pending' => pick('pending', 'chờ chấm'),
    'reviewed' => pick('reviewed', 'đã chấm'),
    'failed' => pick('failed', 'lỗi'),
    'skipped' => pick('skipped', 'bỏ qua'),
    _ => status,
  };

  /// The deterministic families, as the report names them. One method so the
  /// markdown, JSON, HTML and DOCX twins cannot drift on a family label — the
  /// drift the R32 audit series kept finding between the twins.
  String familyLabel(String family) => switch (family) {
    'syllabus' => pick('syllabus', 'syllabus (F7–F9)'),
    'reference' => pick('reference (M2)', 'mùi nhất quán (M2)'),
    'document index' => pick('document index', 'mục lục tài liệu'),
    'diagram audit (vision)' => pick(
      'diagram audit (vision)',
      'chấm sơ đồ (vision)',
    ),
    _ => family,
  };

  String componentState(ComponentState state) => switch (state) {
    ComponentState.passed => pick('passed', 'đạt'),
    ComponentState.failed => pick('failed', 'không đạt'),
    ComponentState.unassessed => pick('unassessed', 'chưa đánh giá'),
  };

  /// How a deterministic row's outcome is printed. One pair, so the markdown,
  /// HTML and DOCX twins cannot disagree on the word.
  String passedFailed(bool passed) =>
      passed ? pick('passed', 'đạt') : pick('failed', 'không đạt');

  String yesNo(bool value) => value ? pick('yes', 'có') : pick('no', 'không');

  /// `run_outcome` from the proxy, in the reader's language.
  String runOutcome(String? outcome) => switch (outcome) {
    'cancelled' => pick('was cancelled', 'đã bị huỷ'),
    'failed' => pick(
      'failed — quota, provider or proxy error',
      'thất bại — hết quota, lỗi nhà cung cấp hoặc proxy',
    ),
    null => pick('not recorded', 'không ghi nhận'),
    _ => pick('completed', 'đã hoàn tất'),
  };

  /// The mode the run actually happened in. The run's own `mock` flag outranks
  /// the current toggle — a report describes the run that happened.
  ///
  /// `short` is the sentence a reader sees next to the rubric version
  /// ("mode: offline mock (no model calls)"); the long form is the standalone
  /// warning the markdown and HTML reports open with.
  String mode(bool offline, {required bool short}) {
    if (offline) {
      return short
          ? pick(
              'offline mock (no model calls)',
              'mô phỏng ngoại tuyến (không gọi model)',
            )
          : pick(
              'Offline mock — not a live AI assessment',
              'Mô phỏng ngoại tuyến — không phải lượt chấm AI thật',
            );
    }
    return short
        ? pick('online proxy', 'trực tuyến qua proxy')
        : pick(
            'Online proxy — not official grading',
            'Trực tuyến qua proxy — không phải điểm chính thức',
          );
  }

  /// The language note every report carries, so a reader is never surprised by
  /// an English quote inside a Vietnamese file.
  String get languageNote => pick(
    'Report language: English. Quoted document text (evidence) and AI-written '
        'suggestions keep the language they were produced in.',
    'Ngôn ngữ báo cáo: Tiếng Việt. Trích dẫn từ tài liệu (bằng chứng) và câu '
        'gợi ý do AI viết vẫn giữ nguyên ngôn ngữ gốc.',
  );
}
