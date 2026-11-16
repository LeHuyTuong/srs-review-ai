import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/core/domain/session_scope.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/course_contract.dart';

/// Firestore-backed repository; checks the session scope before and after
/// every operation.
class FirestoreAcademicRepository
    implements AcademicRepository, CourseCommandRepository {
  FirestoreAcademicRepository(this._service, {this.scope});
  final FirebaseAcademicService _service;
  final SessionScope? scope;

  /// Backend kiểm thử trong bộ nhớ khi Firebase chưa khởi tạo (chỉ test gọi).
  void enableTestBackend() => _service.enableTestBackend();

  @override
  Future<AcademicSnapshot> commitCourse(
    CourseMutation command, {
    required int expectedRevision,
  }) async {
    scope?.requireActive();
    final result = await _service.commitCourse(
      command,
      expectedRevision: expectedRevision,
    );
    scope?.requireActive();
    return result;
  }

  @override
  Future<AcademicSnapshot> load() async {
    scope?.requireActive();
    final result = await _service.load();
    scope?.requireActive();
    return result;
  }

  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) async {
    scope?.requireActive();
    final result = await _service.commit(
      next,
      expectedRevision: expectedRevision,
    );
    scope?.requireActive();
    return result;
  }
}
