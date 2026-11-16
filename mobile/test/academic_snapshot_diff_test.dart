// Mỗi lượt lưu trước đây ghi lại toàn bộ record + meta (~120–300 doc, >3s).
// Chỉ ghi doc thực sự đổi.
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';

void main() {
  AcademicSnapshot snap({String className = 'A', String note = 'x'}) =>
      AcademicSnapshot({
        'revision': 1,
        'classes': [
          {'id': 'c1', 'name': className},
          {'id': 'c2', 'name': 'B'},
        ],
        'courses': [
          {'id': 'k1', 'code': 'K'},
        ],
        'reviewState': {'note': note},
        'dashboard': {'a': 1},
      });

  test('không có bản trước thì ghi đủ', () {
    final w = FirebaseAcademicService.snapshotWrites(null, snap());
    expect(
      w.records.keys,
      containsAll(['classes/c1', 'classes/c2', 'courses/k1']),
    );
    expect(w.meta.keys, containsAll(['reviewState', 'dashboard']));
  });

  test('chỉ ghi record và key meta đã đổi', () {
    final w = FirebaseAcademicService.snapshotWrites(
      snap(),
      snap(className: 'A2', note: 'y'),
    );
    expect(w.records.keys, ['classes/c1']);
    expect(w.meta.keys, ['reviewState']);
  });

  test('không đổi gì thì không ghi record/meta nào', () {
    final w = FirebaseAcademicService.snapshotWrites(snap(), snap());
    expect(w.records, isEmpty);
    expect(w.meta, isEmpty);
  });
}
