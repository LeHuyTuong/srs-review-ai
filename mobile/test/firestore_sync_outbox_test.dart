// Đường ghi Firestore (app thật có Firebase) phải xếp thay đổi vào outbox
// SQLite để AcademicSyncService đẩy lên FastAPI `/sync/push`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/sync/offline_academic_store.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late OfflineAcademicStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fs_outbox');
    store = await OfflineAcademicStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/o.db',
    );
  });
  tearDown(() async {
    await store.db.close();
    await dir.delete(recursive: true);
  });

  AcademicSnapshot seed() => AcademicSnapshot({
    'revision': 3,
    'semesters': [
      {'id': 'fall-2026', 'name': 'Fall 2026'},
    ],
    'courses': <Object>[],
  });

  test('commit qua Firestore service xếp đúng bản ghi mới vào outbox', () async {
    final service = FirebaseAcademicService(null, syncOutbox: store)
      ..enableTestBackend()
      ..injectForTest(seed());
    final next = AcademicSnapshot({
      ...seed().toJson(),
      'semesters': [
        {'id': 'fall-2026', 'name': 'Fall 2026'},
        {'id': 'e2e-1', 'name': 'E2E 1'},
      ],
    });

    final committed = await service.commit(next, expectedRevision: 3);

    expect(committed.revision, 4);
    final ops = await store.outbox();
    expect(ops.map((o) => o.change.key), ['semesters/e2e-1']);
    expect((ops.single.change.data as Map)['name'], 'E2E 1');
  });

  test('không có outbox thì commit vẫn chạy như cũ', () async {
    final service = FirebaseAcademicService(null)
      ..enableTestBackend()
      ..injectForTest(seed());
    final committed = await service.commit(seed(), expectedRevision: 3);
    expect(committed.revision, 4);
    expect(await store.outboxCount(), 0);
  });
}
