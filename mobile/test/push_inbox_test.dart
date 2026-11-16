import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/fcm_service.dart';
import 'package:srs_review_ai_mobile/core/sync/offline_academic_store.dart';
import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/push_inbox_section.dart';

class _Inbox implements PushInboxRepository {
  final records = <String, Map<String, Object?>>{};
  final read = <String>[];
  final controller = StreamController<List<PushInboxItem>>.broadcast();

  @override
  Stream<List<PushInboxItem>> watch(String uid) => controller.stream;

  @override
  Future<void> record(String uid, String id, Map<String, Object?> f) async =>
      records['$uid/$id'] = f;

  @override
  Future<void> markRead(String uid, String id) async => read.add('$uid/$id');
}

class _Store implements FcmTokenStore {
  @override
  Future<void> add(String uid, String token) async {}
  @override
  Future<void> remove(String uid, String token) async {}
}

void main() {
  test('server-sent push is not recorded twice; console push is', () async {
    final inbox = _Inbox();
    await recordPushInInbox(
      inbox,
      'u1',
      const RemoteMessage(
        messageId: 'm1',
        notification: RemoteNotification(title: 'A'),
        data: {'inboxId': 'srv1'},
      ),
    );
    expect(inbox.records, isEmpty);

    await recordPushInInbox(
      inbox,
      'u1',
      const RemoteMessage(
        messageId: 'm2',
        notification: RemoteNotification(title: 'Từ Console', body: 'B'),
        data: {'type': 'review', 'id': 'r9'},
      ),
      read: true,
    );
    expect(inbox.records['u1/m2'], {
      'title': 'Từ Console',
      'body': 'B',
      'type': 'review',
      'targetId': 'r9',
      'source': 'device',
      'read': true,
    });
  });

  testWidgets('foreground push of a signed-in user lands in the inbox', (
    tester,
  ) async {
    final inbox = _Inbox();
    final service = FcmService(
      navigatorKey: GlobalKey<NavigatorState>(),
      tokenStore: _Store(),
      inbox: inbox,
      userIds: Stream.value('u1'),
    );
    // Chỉ cần listener UID; không gọi initialize() vì nó cần plugin thật.
    service.debugListenUser();
    await tester.pump();
    service.showForeground(
      const RemoteMessage(
        messageId: 'm3',
        notification: RemoteNotification(title: 'Hạn nộp'),
      ),
    );
    await tester.pump();
    expect(inbox.records.keys, ['u1/m3']);
  });

  testWidgets('inbox list shows newest pushes, unread count, and opens route', (
    tester,
  ) async {
    final inbox = _Inbox();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushInboxRepositoryProvider.overrideWithValue(inbox),
          pushInboxUidProvider.overrideWith((ref) => Stream.value('u1')),
        ],
        child: MaterialApp(
          onGenerateRoute: (s) => MaterialPageRoute<void>(
            settings: s,
            builder: (_) => s.name == '/'
                ? const Scaffold(
                    body: SingleChildScrollView(child: PushInboxSection()),
                  )
                : Scaffold(body: Text('at ${s.name}')),
          ),
        ),
      ),
    );
    await tester.pump();
    inbox.controller.add(const []);
    await tester.pump();
    expect(find.text('Chưa nhận thông báo đẩy nào.'), findsOneWidget);

    inbox.controller.add([
      PushInboxItem(
        id: 'a',
        title: 'Đã chấm xong',
        body: 'Mở kết quả',
        type: 'review',
        targetId: 'r9',
        receivedAt: DateTime(2026, 11, 6, 9, 5),
      ),
      const PushInboxItem(id: 'b', title: 'Cũ', body: '', read: true),
    ]);
    await tester.pump();
    expect(find.text('1 mới'), findsOneWidget);
    expect(find.text('06/11/2026 · 09:05'), findsOneWidget);

    await tester.tap(find.text('Đã chấm xong'));
    await tester.pumpAndSettle();
    expect(inbox.read, ['u1/a']);
    expect(find.text('at /reviews/r9'), findsOneWidget);
  });

  test('clearUserData wipes snapshot, outbox and cursor but keeps device id', () async {
    sqfliteFfiInit();
    final store = await OfflineAcademicStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final deviceId = await store.deviceId();
    await store.setMeta('pull_cursor', '42');
    await store.committed(
      AcademicSnapshot(const {'courses': []}),
      AcademicSnapshot(const {
        'courses': [
          {'id': 'c1', 'name': 'PRM392'},
        ],
      }),
    );
    expect(await store.restore(), isNotNull);
    expect(await store.outboxCount(), greaterThan(0));

    await store.clearUserData();

    expect(await store.restore(), isNull);
    expect(await store.outboxCount(), 0);
    expect(await store.meta('pull_cursor'), isNull);
    expect(await store.deviceId(), deviceId);
    await store.close();
  });
}
