import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:srs_review_ai/core/contracts/academic/course_contract.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/domain/session_scope.dart';

// Kho mô phỏng trong bộ nhớ giữ dữ liệu đã lưu qua các phiên đăng nhập.
class FakeAcademicService {
  FakeAcademicService(this._bundle);
  final AssetBundle _bundle;
  AcademicSnapshot? _snapshot;
  Future<AcademicSnapshot>? _loading;
  // Dùng lại dữ liệu đã tải hoặc lần tải đang chờ để tránh đọc và khởi tạo kho nhiều lần.
  Future<AcademicSnapshot> load() =>
      _snapshot != null ? Future.value(_snapshot!) : _loading ??= _read();
  Future<AcademicSnapshot> _read() async {
    try {
      return _snapshot = AcademicSnapshotCodec.decode(
        jsonDecode(await _bundle.loadString('assets/fixtures/academic.json')),
      );
    } finally {
      // Xóa dấu đang tải cả khi lỗi để lần thử lại có thể đọc dữ liệu mẫu lần nữa.
      _loading = null;
    }
  }

  // Lưu lệnh Course qua bước kiểm tra phiên bản chung để biểu mẫu cũ không ghi đè dữ liệu mới.
  Future<AcademicSnapshot> commitCourse(
    CourseMutation command,
    int expectedRevision, {
    SessionScope? scope,
  }) async {
    final current = await load();
    scope?.requireActive();
    return commit(command.apply(current), expectedRevision, scope: scope);
  }

  Future<AcademicSnapshot> commit(
    AcademicSnapshot next,
    int expectedRevision, {
    SessionScope? scope,
  }) async {
    await load();
    scope?.requireActive();
    final current = _snapshot!;
    // Từ chối bản nháp dựa trên revision cũ trước khi thay dữ liệu chung.
    if (current.revision != expectedRevision) {
      throw const AcademicFailure(
        'Dữ liệu đã thay đổi. Đóng form và mở lại để tiếp tục.',
        code: AcademicErrorCode.conflict,
      );
    }
    // Kiểm tra toàn bộ Course trước khi lưu; mã môn trùng chỉ khác hoa thường cũng bị từ chối.
    final ids = <String>{}, codes = <String>{};
    for (final course in next.courses) {
      CourseDto.fromJson(course.toJson());
      if (course.id.isEmpty || !ids.add(course.id)) {
        throw const AcademicFailure('ID môn học đã tồn tại hoặc không hợp lệ.');
      }
      if (!codes.add(course.code.trim().toUpperCase())) {
        throw const AcademicFailure('Mã môn đã tồn tại.');
      }
    }
    // Chỉ tăng revision sau khi mọi kiểm tra thành công để các biểu mẫu cũ nhận biết xung đột.
    return _snapshot = AcademicSnapshot({
      ...next.toJson(),
      'revision': current.revision + 1,
    });
  }
}
