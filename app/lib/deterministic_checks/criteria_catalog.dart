/// The checklist of evaluation criteria the app applies — one entry per
/// [CheckId], grouped by the rulebook family it belongs to.
///
/// Why a catalog instead of prose inside the view: the drift to guard
/// against is adding a CheckId (a new rule) without ever telling the user it
/// exists. A test asserts exact coverage of [CheckId.values], so a new check
/// fails the suite until it appears on the user-facing checklist — the same
/// "adding a CheckId without adding it here is the drift to watch for"
/// contract `contracts/review.schema.json` states for the wire enum.
///
/// Wording is for students, not implementers: each entry says what is being
/// judged and where it is judged, never how (the how lives in
/// `review-rules/`). `family` is always derived from the [CheckId] getters —
/// never hand-assigned — so it cannot drift from the dashboard grouping.
library;

import 'models/deterministic_finding.dart';

/// Where a criterion runs and what it costs.
enum CriterionFamily {
  /// Syllabus thresholds (F7–F9): offline, zero tokens.
  syllabus('Theo Syllabus', 'Chạy ngoại tuyến, 0 token'),

  /// Consistency smells (M2 + rulebook §F furniture).
  reference('Mùi nhất quán', 'Chạy ngoại tuyến, 0 token'),

  /// The document's own index (blueprint checks).
  blueprint('Mục lục tài liệu', 'Chạy ngoại tuyến, 0 token'),

  /// §F.5 format & layout — heading numbering, page numbers at page end.
  format('Format & Layout', 'Chạy ngoại tuyến, 0 token'),

  /// Page images through the vision audit — the only AI-priced family.
  vision('Chấm bằng hình ảnh', 'AI · tốn lượt gọi, chạy khi bạn bấm audit');

  const CriterionFamily(this.title, this.cost);

  final String title;
  final String cost;
}

/// One row of the checklist.
class Criterion {
  const Criterion(this.check, this.what);

  final CheckId check;

  /// One sentence a student can check against their own document.
  final String what;

  CriterionFamily get family => familyFor(check);
}

/// The family a check belongs to, derived from the [CheckId] getters so the
/// checklist and the dashboard grouping can never disagree.
CriterionFamily familyFor(CheckId check) {
  if (check == CheckId.diagramAudit) return CriterionFamily.vision;
  if (check.isFormatCheck) return CriterionFamily.format;
  if (check.isBlueprintCheck) return CriterionFamily.blueprint;
  if (check.isReferenceCheck) return CriterionFamily.reference;
  return CriterionFamily.syllabus;
}

/// Every criterion the app evaluates, in dashboard order. Coverage of
/// [CheckId.values] is asserted by `criteria_catalog_test.dart`.
const List<Criterion> kCriteriaChecklist = [
  Criterion(
    CheckId.ucCount,
    'Tài liệu có đủ số Use Case tối thiểu theo Syllabus.',
  ),
  Criterion(
    CheckId.language,
    'Tài liệu viết bằng tiếng Anh (kiểm sơ bộ ngoài ASCII).',
  ),
  Criterion(CheckId.ucSize, 'Mỗi Use Case cỡ vừa có 3–7 bước xử lý.'),
  Criterion(
    CheckId.duplicateIds,
    'Một mã yêu cầu (UC04…) bị dùng cho nhiều chức năng khác nhau.',
  ),
  Criterion(
    CheckId.missingPostcondition,
    'Use Case không nêu hậu điều kiện — không biết khi nào coi là xong.',
  ),
  Criterion(
    CheckId.crossArtifactName,
    'Cùng một thực thể bị đặt nhiều tên khác nhau giữa các mục.',
  ),
  Criterion(
    CheckId.missingActor,
    'Use Case không nói ai/hệ thống nào khởi chạy.',
  ),
  Criterion(
    CheckId.ambiguousWording,
    'Câu chữ mơ hồ, không có ngưỡng đo được ("nhanh chóng", "thân thiện").',
  ),
  Criterion(
    CheckId.placeholderTbd,
    'Còn sót chỗ trống TBD / "chưa xác định" trong bản nộp.',
  ),
  Criterion(CheckId.missingPriority, 'Yêu cầu thiếu trường độ ưu tiên.'),
  Criterion(
    CheckId.diagramAudit,
    'Sơ đồ được chấm bằng hình ảnh trang (vision audit) khi bạn bấm chạy.',
  ),
  Criterion(
    CheckId.nfrUnquantified,
    'Yêu cầu phi chức năng không kèm con số/điều kiện đo.',
  ),
  Criterion(
    CheckId.duplicateCaption,
    'Mục lục có hai bảng/hình cùng tên — không phân biệt được khi truy vết.',
  ),
  Criterion(
    CheckId.numberingGap,
    'Số bảng/hình bị nhảy trong mục lục (xoá mà quên cập nhật).',
  ),
  Criterion(
    CheckId.missingSection,
    'Báo cáo thiếu một phần bắt buộc (Introduction, SRS, Design…).',
  ),
  Criterion(
    CheckId.unclassifiedFigure,
    'Hình không nói rõ đây là loại sơ đồ gì (class, sequence, ERD…).',
  ),
  Criterion(
    CheckId.captionPageMismatch,
    'Mục lục trỏ sai trang so với nơi caption thật nằm.',
  ),
  Criterion(
    CheckId.tablePositionDrift,
    'Bảng/hình bị dời ra xa trang mà mục lục khai báo (mục lục chưa Update Field).',
  ),
  Criterion(
    CheckId.coverPageInfo,
    'Trang bìa thiếu tên đề tài / giảng viên hướng dẫn / nhóm-thành viên.',
  ),
  Criterion(
    CheckId.headerFooterConsistency,
    'Header/footer đổi nội dung giữa các trang — dấu hiệu ráp hai bản tài liệu.',
  ),
  Criterion(
    CheckId.projectInfoMismatch,
    'Thông tin khai báo ở form (tên đề tài, GVHD) không khớp với trang bìa.',
  ),
  Criterion(
    CheckId.sectionOrder,
    'Các chương chồng lên nhau hoặc sai thứ tự theo mục lục.',
  ),
  Criterion(
    CheckId.headingNumbering,
    'Heading đánh số tạo thành phân cấp (3.1 cần có 3) và số hiệu không trùng.',
  ),
  Criterion(
    CheckId.pageNumbering,
    'Số trang thấy ở dòng cuối mỗi trang (tài liệu ≥ 6 trang).',
  ),
];
