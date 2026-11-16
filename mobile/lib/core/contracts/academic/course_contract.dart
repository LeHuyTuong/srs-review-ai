import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Course là phần đầu tiên có DTO kiểm tra dữ liệu đầu vào khi chuẩn bị chuyển nguồn dữ liệu.
// Giữ trường dữ liệu cũ chưa biết, nhưng kiểm tra kiểu trước khi đọc các trường bắt buộc.
class CourseDto {
  CourseDto._(this._record);
  final AcademicRecord _record;
  String get id => _record.id;
  String get code => _record.text('code');
  String get name => _record.name;
  AcademicJson toJson() => _record.toJson();
  // Kiểm tra kiểu và trường bắt buộc trước khi chuẩn hóa mã môn; giữ các trường cũ khi chuyển DTO.
  factory CourseDto.fromJson(
    Object? value, {
    bool requireId = true,
    AcademicErrorCode errorCode = AcademicErrorCode.invalidData,
  }) {
    if (value is! Map<String, dynamic> ||
        value['code'] is! String ||
        (value['code'] as String).trim().isEmpty ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        (value['id'] != null && value['id'] is! String) ||
        (requireId && (value['id'] as String? ?? '').isEmpty)) {
      throw AcademicFailure(
        'Dữ liệu môn học không hợp lệ. Nhập mã và tên môn học.',
        code: errorCode,
      );
    }
    return CourseDto._(
      AcademicRecord({
        ...value,
        'code': (value['code'] as String).trim().toUpperCase(),
        'name': (value['name'] as String).trim(),
      }),
    );
  }
}

// Phân biệt rõ tạo mới và cập nhật để lệnh tạo không ghi đè môn học đã có.
class CourseMutation {
  CourseMutation({
    required this.course,
    required this.id,
    required this.create,
  });
  final CourseDto course;
  final String id;
  final bool create;
  AcademicSnapshot apply(AcademicSnapshot current) {
    final existing = current.course(id);
    if (create && existing != null) {
      throw const AcademicFailure(
        'ID môn học đã tồn tại. Vui lòng thử lại.',
        code: AcademicErrorCode.conflict,
      );
    }
    if (!create && existing == null) {
      throw const AcademicFailure(
        'Không tìm thấy môn học.',
        code: AcademicErrorCode.notFound,
      );
    }
    // So mã môn sau khi chuẩn hóa chữ hoa, loại trừ chính môn đang cập nhật.
    if (current.courses.any(
      (c) => c.id != id && c.code.trim().toUpperCase() == course.code,
    )) {
      throw const AcademicFailure('Mã môn đã tồn tại.');
    }
    // Ghép dữ liệu mới lên bản cũ để giữ trường chưa chuyển đổi; chỉ thêm dòng khi là lệnh tạo.
    final row = {...?existing?.toJson(), ...course.toJson(), 'id': id};
    return current.replaceCollection('courses', [
      for (final old in current.courses)
        if (old.id == id) row else old.toJson(),
      if (create) row,
    ]);
  }
}

// Hợp đồng lệnh Course bổ sung vẫn tương thích với cách ghi toàn bộ dữ liệu hiện tại.
// Khi nối Firestore, phía máy chủ phải kiểm tra UID, phạm vi và phiên bản mong đợi,
// rồi thực hiện lệnh nguyên tử; không tin toàn bộ dữ liệu do máy khách gửi lên.
abstract interface class CourseCommandRepository {
  Future<AcademicSnapshot> commitCourse(
    CourseMutation command, {
    required int expectedRevision,
  });
}

// Kiểm tra cấu trúc dữ liệu học vụ và các Course trước khi tạo bản chụp bất biến.
abstract final class AcademicSnapshotCodec {
  static AcademicSnapshot decode(Object? value) {
    if (value is! Map<String, dynamic> || value['courses'] is! List) {
      throw const AcademicFailure(
        'Dữ liệu học vụ không hợp lệ.',
        code: AcademicErrorCode.invalidData,
      );
    }
    for (final row in value['courses'] as List) {
      CourseDto.fromJson(row);
    }
    return AcademicSnapshot(value);
  }
}
