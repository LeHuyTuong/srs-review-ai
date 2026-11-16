import 'package:srs_review_ai/core/contracts/academic/academic_repository.dart';
import 'package:srs_review_ai/core/contracts/academic/course_contract.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/domain/session_scope.dart';
import 'package:srs_review_ai/features/academic/data/services/fake_academic_service.dart';

// Repository mô phỏng dùng chung dữ liệu giữa Course, Class, Rule Set và Tổng quan.
class FakeAcademicRepository
    implements AcademicRepository, CourseCommandRepository {
  const FakeAcademicRepository(this._service, {this.scope});
  final FakeAcademicService _service;
  final SessionScope? scope;
  @override
  Future<AcademicSnapshot> commitCourse(
    CourseMutation command, {
    required int expectedRevision,
  }) => _service.commitCourse(command, expectedRevision, scope: scope);
  @override
  Future<AcademicSnapshot> load() async {
    scope?.requireActive();
    // Kiểm tra phiên cả trước và sau khi tải vì người dùng có thể đăng xuất trong lúc chờ.
    final result = await _service.load();
    scope?.requireActive();
    return result;
  }

  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) => _service.commit(next, expectedRevision, scope: scope);
}
