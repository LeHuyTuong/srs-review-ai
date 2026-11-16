import 'dart:io';
import 'dart:convert';

import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/repositories/academic/academic_repository.dart';

AcademicSnapshot academicFixture() => AcademicSnapshot(
  jsonDecode(File('assets/fixtures/academic.json').readAsStringSync())
      as AcademicJson,
);

/// Kho kiểm thử cho phép tiêm lỗi tải/ghi và kiểm tra commit nguyên tử.
class TestAcademicRepository implements AcademicRepository {
  TestAcademicRepository(this.snapshot);
  AcademicSnapshot snapshot;
  bool failLoad = false, failWrite = false;
  int loads = 0;
  @override
  Future<AcademicSnapshot> load() async {
    loads++;
    if (failLoad) throw const AcademicFailure('Lỗi thử nghiệm');
    return snapshot;
  }

  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) async {
    if (failWrite) throw const AcademicFailure('Không thể lưu. Thử lại.');
    if (snapshot.revision != expectedRevision) {
      throw const AcademicFailure('Xung đột phiên bản');
    }
    snapshot = AcademicSnapshot({
      ...next.toJson(),
      'revision': expectedRevision + 1,
    });
    return snapshot;
  }
}
