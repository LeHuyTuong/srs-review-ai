import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/session_scope.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/course_contract.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/academic_persistence.dart';

// Kho học vụ giữ dữ liệu đã lưu qua các phiên đăng nhập.
// Có [persistence] (SQLite trên máy thật) thì snapshot sống qua lần tắt app và
// mọi thay đổi được xếp vào outbox để đồng bộ; không có thì chỉ nằm trong RAM.
class FakeAcademicService {
  FakeAcademicService(this._bundle, {this.persistence});
  final AssetBundle _bundle;
  final AcademicPersistence? persistence;
  AcademicSnapshot? _snapshot;
  Future<AcademicSnapshot>? _loading;
  // Chuỗi tuần tự hoá commit và merge từ server: cả hai đọc-sửa-ghi _snapshot
  // qua một lần await ghi bền, chạy chồng nhau thì lượt sau đè mất lượt trước.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // Dùng lại dữ liệu đã tải hoặc lần tải đang chờ để tránh đọc và khởi tạo kho nhiều lần.
  Future<AcademicSnapshot> load() =>
      _snapshot != null ? Future.value(_snapshot!) : _loading ??= _read();
  Future<AcademicSnapshot> _read() async {
    try {
      final saved = await persistence?.restore();
      if (saved != null) {
        return _snapshot = AcademicSnapshotCodec.decode(saved);
      }
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
    return _serial(() => _commit(next, expectedRevision, scope: scope));
  }

  Future<AcademicSnapshot> _commit(
    AcademicSnapshot next,
    int expectedRevision, {
    SessionScope? scope,
  }) async {
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
    final saved = AcademicSnapshot({
      ...next.toJson(),
      'revision': current.revision + 1,
    });
    // Ghi bền trước khi công bố: lỗi ở đây giữ nguyên snapshot cũ trong RAM.
    await persistence?.committed(current, saved);
    return _snapshot = saved;
  }

  /// Áp thay đổi kéo từ server. [change] chạy BÊN TRONG chuỗi tuần tự, nên nó
  /// thấy outbox đúng như sau commit gần nhất; trả `null` = không có gì để áp.
  /// Tăng revision để biểu mẫu đang mở trên bản cũ nhận ra xung đột thay vì
  /// lặng lẽ ghi đè thay đổi vừa đồng bộ về.
  Future<AcademicSnapshot?> mergeExternal(
    Future<AcademicJson?> Function(AcademicJson current) change,
  ) async {
    await load();
    return _serial(() async {
      final current = _snapshot!;
      final next = await change(current.toJson());
      if (next == null) return null;
      final merged = AcademicSnapshot({
        ...next,
        'revision': current.revision + 1,
      });
      await persistence?.merged(merged);
      return _snapshot = merged;
    });
  }
}
