import 'package:srs_review_ai/core/domain/academic/academic_models.dart';

// Hợp đồng kho học vụ để có thể thay nguồn bằng Firestore mà không sửa Widget.
abstract interface class AcademicRepository {
  Future<AcademicSnapshot> load();
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  });
}
