import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Quy tắc kiểm tra thuần Dart dùng chung ở biểu mẫu và lệnh ghi dữ liệu.
abstract final class AcademicPolicy {
  // Kiểm tra cấu hình nộp bài và tiêu chí trước khi lưu hoặc chạy AI; trả lỗi đầu tiên tìm thấy.
  static String? validateRule(AcademicJson r) {
    bool finite(String k) => r[k] is num && (r[k] as num).isFinite;
    if ((r['id']?.toString().trim() ?? '').isEmpty ||
        (r['name']?.toString().trim() ?? '').isEmpty) {
      return 'Cần ID và tên bộ quy tắc.';
    }
    if ((r['allowedFormats'] as List? ?? []).isEmpty ||
        !finite('maxFileSizeMB') ||
        (r['maxFileSizeMB'] as num) <= 0 ||
        !finite('reviewSlaDays') ||
        (r['reviewSlaDays'] as num) <= 0) {
      return 'Định dạng, dung lượng và hạn đánh giá phải hợp lệ.';
    }
    final max = r['maxResubmissions'];
    if (max != null &&
        (max is! num || !max.isFinite || max < 0 || max % 1 != 0)) {
      return 'Số lần nộp lại phải là số nguyên không âm.';
    }
    // Không được bắt buộc AI trước giảng viên nếu chức năng AI đang tắt.
    if (r['aiRequiredBeforeSupervisor'] == true && r['aiEnabled'] != true) {
      return 'Không thể bắt buộc AI khi AI bị tắt.';
    }
    // Hai ngưỡng phải hữu hạn, nằm trong khoảng 0–100 và ngưỡng đạt phải cao hơn ngưỡng cải thiện.
    if (!finite('passThreshold') ||
        !finite('improveThreshold') ||
        (r['passThreshold'] as num) > 100 ||
        (r['improveThreshold'] as num) < 0 ||
        (r['passThreshold'] as num) <= (r['improveThreshold'] as num)) {
      return 'Ngưỡng cần cải thiện phải thấp hơn ngưỡng đạt (0–100%).';
    }
    final cs = (r['criteria'] as List? ?? []).cast<AcademicJson>();
    if (cs.map((c) => c['id']).toSet().length != cs.length ||
        cs.any(
          (c) =>
              (c['id']?.toString().trim() ?? '').isEmpty ||
              (c['name']?.toString().trim() ?? '').isEmpty ||
              c['maxScore'] is! num ||
              !(c['maxScore'] as num).isFinite ||
              (c['maxScore'] as num) <= 0,
        )) {
      return 'Tiêu chí cần ID duy nhất, tên và điểm tối đa lớn hơn 0.';
    }
    // Chỉ kích hoạt khi có tiêu chí bật và không bị đánh dấu thiếu cấu hình danh sách kiểm tra.
    if (r['status'] == 'active' &&
        (!cs.any((c) => c['enabled'] == true) ||
            r['templateMissing'] == true)) {
      return 'Cần ít nhất một tiêu chí bật và checklist đầy đủ trước khi kích hoạt.';
    }
    // Rule Set bắt buộc AI phải có ít nhất một tiêu chí đang bật cho AI xử lý.
    if (r['status'] == 'active' &&
        r['aiRequiredBeforeSupervisor'] == true &&
        !cs.any((c) => c['enabled'] == true && c['aiEnabled'] == true)) {
      return 'Cần ít nhất một tiêu chí bật AI để bắt buộc Đánh giá AI.';
    }
    return null;
  }

  // Tạo Rule Set ở trạng thái draft để người dùng bổ sung tiêu chí trước khi kích hoạt.
  static AcademicJson newRule(String id) => {
    'id': id,
    'name': '',
    'description': '',
    'version': 1,
    'status': 'draft',
    'aiEnabled': true,
    'aiReview': 'manual',
    'aiRequiredBeforeSupervisor': false,
    'supervisorApproval': true,
    'prerequisiteApproval': true,
    'resubmissionEnabled': true,
    'allowedFormats': ['PDF', 'DOCX'],
    'maxFileSizeMB': 20,
    'reviewSlaDays': 3,
    'documentType': 'Tất cả',
    'criteria': <AcademicJson>[],
    'passThreshold': 80,
    'improveThreshold': 70,
    'scoringMode': 'weighted',
  };
  static AcademicJson newCriterion(String id) => {
    'id': id,
    'name': '',
    'description': '',
    'maxScore': 10,
    'enabled': true,
    'required': false,
    'critical': false,
    'evidenceRequired': true,
    'aiEnabled': true,
    'instruction': '',
    'evidenceRequirement': '',
    'suggestScore': true,
    'suggestFindings': true,
    'suggestSuggestions': true,
  };

  // Kiểm tra đợt học, khoảng ngày, giới hạn và mã lớp; lớp đã có nhóm không được chuyển đợt.
  static String? validateClass(
    AcademicJson v,
    AcademicSnapshot s,
    ClassRoom? old,
  ) {
    if ((v['code']?.toString().trim() ?? '').isEmpty) return 'Nhập mã lớp.';
    final off = s.offering(v['offeringId'] as String? ?? '');
    if (off == null) return 'Chọn môn học trong học kỳ.';
    final start = DateTime.tryParse(v['startDate']?.toString() ?? '');
    final end = DateTime.tryParse(v['endDate']?.toString() ?? '');
    if (start == null || end == null || !end.isAfter(start)) {
      return 'Ngày kết thúc phải sau ngày bắt đầu.';
    }
    for (final key in ['capacity', 'maxGroupMembers']) {
      final n = v[key];
      if (n is! num || !n.isFinite || n <= 0 || n % 1 != 0) {
        return key == 'capacity'
            ? 'Sĩ số tối đa phải là số nguyên dương.'
            : 'Số thành viên tối đa mỗi nhóm phải là số nguyên dương.';
      }
    }
    if (old != null &&
        (old.groupCount > 0 || s.classGroups(old.id).isNotEmpty) &&
        off.id != old.offeringId) {
      return 'Lớp đã có nhóm nên không thể chuyển sang môn học khác.';
    }
    if (s.classes.any(
      (c) =>
          c.id != old?.id &&
          c.code.toUpperCase() == v['code'].toString().trim().toUpperCase(),
    )) {
      return 'Mã lớp đã tồn tại.';
    }
    return null;
  }

  // Hạ giới hạn không xóa người cũ; khi thêm phải còn chỗ và thuộc đúng lớp.
  static void checkMember(
    AcademicSnapshot s,
    StudentGroup group,
    String studentId,
  ) {
    final cls = s.classRoom(group.classId);
    if (cls == null || cls.archived) {
      throw const AcademicFailure('Lớp đã lưu trữ hoặc không còn tồn tại.');
    }
    final student = s.students.where((v) => v.id == studentId).firstOrNull;
    if (student == null || !student.belongsTo(cls.id)) {
      throw const AcademicFailure('Sinh viên phải thuộc đúng lớp của nhóm.');
    }
    if (s.classGroups(cls.id).any((g) => g.memberIds.contains(studentId))) {
      throw const AcademicFailure('Sinh viên đã có nhóm trong lớp.');
    }
    if (group.memberIds.length >= cls.memberLimit) {
      throw const AcademicFailure('Nhóm đã đạt giới hạn thành viên của lớp.');
    }
  }

  // Bản sao đổi ID cả Lab/mục, ánh xạ phụ thuộc và không chia sẻ cấu trúc ghi.
  static List<AcademicJson> cloneLabs(
    List<AcademicLab> labs,
    String Function(String) id,
  ) {
    // Tạo bảng ánh xạ ID mục trước, rồi đổi các liên kết phụ thuộc sang ID của bản sao.
    final ids = {for (final i in labs.expand((l) => l.items)) i.id: id('item')};
    return [
      for (final l in labs)
        {
          ...l.toJson(),
          'id': id('lab'),
          'items': [
            for (final i in l.items)
              {
                ...i.toJson(),
                'id': ids[i.id],
                'dependsOn': i.dependencies.map((d) => ids[d] ?? d).toList(),
              },
          ],
        },
    ];
  }
}
