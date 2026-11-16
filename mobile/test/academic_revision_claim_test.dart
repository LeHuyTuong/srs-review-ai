// Hai thiết bị cùng ghi reviewState: kiểm revision phải so với server,
// không phải bản cache của chính thiết bị — nếu không, máy ghi sau đè mất
// yêu cầu máy kia vừa tạo (last-writer-wins, đo được 11/11/2026).
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';

void main() {
  AcademicSnapshot seed() => AcademicSnapshot({
    'revision': 3,
    'semesters': [
      {'id': 'fall-2026', 'name': 'Fall 2026'},
    ],
    'courses': <Object>[],
  });

  test('server đã sang revision mới thì commit từ cache cũ bị từ chối', () async {
    final service = FirebaseAcademicService(null)
      ..enableTestBackend()
      ..injectForTest(seed())
      ..serverRevisionForTest = 4; // thiết bị khác vừa ghi
    final next = AcademicSnapshot({...seed().toJson(), 'currentSemesterId': 'x'});

    await expectLater(
      service.commit(next, expectedRevision: 3),
      throwsA(
        isA<AcademicFailure>().having(
          (e) => e.code,
          'code',
          AcademicErrorCode.conflict,
        ),
      ),
    );
    expect(service.serverRevisionForTest, 4);
  });

  test('server khớp revision thì commit chiếm revision kế tiếp', () async {
    final service = FirebaseAcademicService(null)
      ..enableTestBackend()
      ..injectForTest(seed())
      ..serverRevisionForTest = 3;
    final next = AcademicSnapshot({...seed().toJson(), 'currentSemesterId': 'x'});

    final committed = await service.commit(next, expectedRevision: 3);

    expect(committed.revision, 4);
    expect(service.serverRevisionForTest, 4);
  });
}
