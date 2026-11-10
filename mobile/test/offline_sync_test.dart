// Đồng bộ offline: SQLite trên máy ↔ FastAPI `/sync/*` THẬT.
//
// Không dùng TestWidgetsFlutterBinding: binding đó thay HttpClient bằng bản
// luôn trả 400, nên test chạy server thật sẽ "xanh" mà không gọi được server.
// Fixture được đọc thẳng từ đĩa qua [_DiskBundle].
//
// Test tích hợp tự bật `server/tests/support/sync_test_server.py` (venv của
// server); "mất mạng" = server chưa chạy / bị tắt giữa chừng.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srs_review_ai_mobile/core/contracts/academic/academic_persistence.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/sync/academic_sync_service.dart';
import 'package:srs_review_ai_mobile/core/sync/offline_academic_store.dart';
import 'package:srs_review_ai_mobile/core/sync/record_change.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/fake_academic_service.dart';

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

AcademicJson _fixture() =>
    jsonDecode(File('assets/fixtures/academic.json').readAsStringSync())
        as AcademicJson;

Map<String, dynamic> _withoutRevision(AcademicJson s) =>
    jsonDecode(jsonEncode({...s}..remove('revision'))) as Map<String, dynamic>;

/// Một "máy": file SQLite riêng + kho học vụ + dịch vụ đồng bộ.
class _Device {
  _Device(this.dbPath, this.port);
  final String dbPath;
  final int port;
  late OfflineAcademicStore store;
  late FakeAcademicService academic;
  late AcademicSyncService sync;
  int remoteApplied = 0;

  Future<_Device> boot() async {
    store = await OfflineAcademicStore.open(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    academic = FakeAcademicService(_DiskBundle(), persistence: store);
    sync = AcademicSyncService(
      store: store,
      academic: academic,
      transport: HttpSyncTransport(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        idToken: () async => 'test:teacher-1',
        timeout: const Duration(seconds: 3),
      ),
      onRemoteApplied: () => remoteApplied++,
      idleInterval: const Duration(hours: 1),
    );
    return this;
  }

  Future<void> shutdown() async {
    sync.dispose();
    await store.close();
  }

  Future<String> courseName(String id) async =>
      (await academic.load()).course(id)!.name;

  Future<void> renameCourse(String id, String name) async {
    final current = await academic.load();
    final json = current.toJson();
    json['courses'] = [
      for (final c in json['courses'] as List)
        if ((c as Map)['id'] == id) {...c, 'name': name} else c,
    ];
    await academic.commit(AcademicSnapshot(json), current.revision);
  }
}

class _Server {
  _Server(this.port, this.cacheDir);
  final int port;
  final String cacheDir;
  Process? _process;

  static String get python => Platform.isWindows
      ? '../server/.venv/Scripts/python.exe'
      : '../server/.venv/bin/python';
  static bool get available => File(python).existsSync();

  Future<void> start() async {
    _process = await Process.start(
      python,
      ['tests/support/sync_test_server.py', '$port'],
      workingDirectory: '../server',
      environment: {'SRS_CACHE_DIR': cacheDir, 'DATABASE_URL': ''},
    );
    _process!.stderr.transform(utf8.decoder).listen(stderr.write);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final c = HttpClient();
        final res = await (await c.getUrl(
          Uri.parse('http://127.0.0.1:$port/health'),
        )).close();
        c.close(force: true);
        if (res.statusCode == 200) return;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw StateError('sync test server did not start on :$port');
  }

  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    p.kill();
    await p.exitCode;
    _process = null;
  }
}

/// Ghi bền hỏng KHÔNG đồng bộ (như đĩa đầy giữa transaction): chỉ `await`
/// mới bắt được — DB đã đóng thì ném ngay nên không phân biệt được.
class _LateFailingPersistence implements AcademicPersistence {
  @override
  Future<AcademicJson?> restore() async => null;
  @override
  Future<void> committed(AcademicSnapshot before, AcademicSnapshot after) =>
      Future<void>.delayed(
        const Duration(milliseconds: 5),
        () => throw StateError('disk full'),
      );
  @override
  Future<void> merged(AcademicSnapshot after) async {}
}

/// Chạy [beforePull] đúng một lần ngay trước GET /sync/pull — mô phỏng người
/// dùng bấm lưu giữa lúc push đã xong và pull chưa áp.
class _InterceptingTransport implements SyncTransport {
  _InterceptingTransport(this.inner, this.beforePull);
  final SyncTransport inner;
  Future<void> Function()? beforePull;
  @override
  Future<SyncResponse> get(String path, Map<String, String> query) async {
    final hook = beforePull;
    beforePull = null;
    await hook?.call();
    return inner.get(path, query);
  }

  @override
  Future<SyncResponse> post(String path, Object body) => inner.post(path, body);
  @override
  void close() => inner.close();
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  sqfliteFfiInit();

  group('diff/apply', () {
    test('apply(diff(a, b)) on a reproduces b for the real fixture', () {
      final a = _fixture();
      final b = jsonDecode(jsonEncode(a)) as AcademicJson;
      (b['courses'] as List).first['name'] = 'Đổi tên';
      (b['classes'] as List).removeAt(1);
      (b['groups'] as List).add({'id': 'grp-new', 'name': 'Nhóm mới'});
      (b['reviewState'] as Map)['requests'] = [];
      b['currentSemesterId'] = 'sem-x';
      b['revision'] = 99;

      final changes = diffSnapshots(a, b);
      expect(changes.map((c) => c.key), {
        'courses/${(a['courses'] as List).first['id']}',
        'classes/${(a['classes'] as List)[1]['id']}',
        'groups/grp-new',
        '_root/reviewState',
        '_root/currentSemesterId',
      });
      expect(
        changes.firstWhere((c) => c.collection == 'classes').deleted,
        true,
      );
      expect(_withoutRevision(applyChanges(a, changes)), _withoutRevision(b));
    });

    test('identical snapshots produce no change; revision never syncs', () {
      final a = _fixture();
      expect(diffSnapshots(a, {...a, 'revision': 7}), isEmpty);
    });
  });

  group('SQLite persistence', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('srs-sync-'));
    tearDown(() async => dir.delete(recursive: true));

    test(
      'commit survives a restart and queues exactly the changed record',
      () async {
        final path = '${dir.path}/a.db';
        final first = await _Device(path, 1).boot();
        final id = (await first.academic.load()).courses.first.id;
        await first.renameCourse(id, 'Lưu offline');
        final ops = await first.store.outbox();
        expect(ops.map((o) => o.change.key), ['courses/$id']);
        expect((ops.single.change.data! as Map)['name'], 'Lưu offline');
        await first.shutdown();

        final again = await _Device(path, 1).boot();
        expect(await again.courseName(id), 'Lưu offline');
        expect(await again.store.outboxCount(), 1);
        await again.shutdown();
      },
    );

    test(
      'a failed durable write rejects the commit and keeps RAM unchanged',
      () async {
        final device = await _Device('${dir.path}/b.db', 1).boot();
        final before = await device.academic.load();
        await device.store.close(); // ghi bền sẽ ném lỗi
        await expectLater(
          device.renameCourse(before.courses.first.id, 'Không được lưu'),
          throwsA(anything),
        );
        expect(identical(await device.academic.load(), before), true);
        device.sync.dispose();
      },
    );
  });

  test('durable write failing late still fails the commit', () async {
    final academic = FakeAcademicService(
      _DiskBundle(),
      persistence: _LateFailingPersistence(),
    );
    final before = await academic.load();
    final json = before.toJson()..['now'] = 1;
    await expectLater(
      academic.commit(AcademicSnapshot(json), before.revision),
      throwsA(isA<StateError>()),
    );
    expect(identical(await academic.load(), before), true);
  });

  group('sync against the real FastAPI server', () {
    late Directory dir;
    late _Server server;
    late int port;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('srs-sync-e2e-');
      port = await _freePort();
      server = _Server(port, '${dir.path}/server-cache');
    });
    tearDown(() async {
      await server.stop();
      for (var i = 0; i < 5; i++) {
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    test('offline edit is kept, pushed when the server returns, and reaches '
        'a second device', () async {
      final a = await _Device('${dir.path}/a.db', port).boot();
      final b = await _Device('${dir.path}/b.db', port).boot();
      final id = (await a.academic.load()).courses.first.id;

      // Mất mạng: server chưa chạy.
      await a.renameCourse(id, 'Sửa lúc offline');
      expect(await a.sync.syncNow(), SyncOutcome.offline);
      expect(a.sync.online, false);
      expect(a.sync.pending, 1);
      expect((await a.store.outbox()).single.attempts, 1);
      expect(a.sync.nextDelay(SyncOutcome.offline), const Duration(seconds: 2));

      // Có mạng lại.
      await server.start();
      expect(await a.sync.syncNow(), SyncOutcome.ok);
      expect(a.sync.online, true);
      expect(a.sync.pending, 0);

      expect(await b.courseName(id), isNot('Sửa lúc offline'));
      expect(await b.sync.syncNow(), SyncOutcome.ok);
      expect(await b.courseName(id), 'Sửa lúc offline');
      expect(b.remoteApplied, 1);

      // Bản kéo về được lưu SQLite trên máy B, không vào outbox của B.
      await b.shutdown();
      final bAgain = await _Device('${dir.path}/b.db', port).boot();
      expect(await bAgain.courseName(id), 'Sửa lúc offline');
      expect(await bAgain.store.outboxCount(), 0);
      await bAgain.shutdown();
      await a.shutdown();
    }, skip: _Server.available ? false : 'server/.venv chưa có');

    test('conflict: later edit wins on both devices; pending local edit is not '
        'overwritten by a pull', () async {
      await server.start();
      final a = await _Device('${dir.path}/a.db', port).boot();
      final b = await _Device('${dir.path}/b.db', port).boot();
      final courses = (await a.academic.load()).courses;
      final x = courses[0].id, y = courses[1].id;

      await a.renameCourse(x, 'A sửa trước');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.renameCourse(x, 'B sửa sau');
      expect(await b.sync.syncNow(), SyncOutcome.ok); // B lên trước
      expect(await a.sync.syncNow(), SyncOutcome.ok); // A cũ hơn → stale
      expect(await a.courseName(x), 'B sửa sau');
      expect(await a.store.outboxCount(), 0);
      expect(await b.sync.syncNow(), SyncOutcome.ok);
      expect(await b.courseName(x), 'B sửa sau');

      // A đẩy y lên; B đang có sửa y chưa gửi (mất mạng) → pull không đè.
      await a.renameCourse(y, 'A sửa y');
      expect(await a.sync.syncNow(), SyncOutcome.ok);
      await server.stop();
      await b.renameCourse(y, 'B sửa y offline');
      expect(await b.sync.syncNow(), SyncOutcome.offline);
      await server.start(); // cùng SRS_CACHE_DIR: dữ liệu server còn nguyên
      expect(await b.sync.syncNow(), SyncOutcome.ok);
      expect(await b.courseName(y), 'B sửa y offline');
      expect(await a.sync.syncNow(), SyncOutcome.ok);
      expect(await a.courseName(y), 'B sửa y offline');

      await a.shutdown();
      await b.shutdown();
    }, skip: _Server.available ? false : 'server/.venv chưa có');

    test(
      'an edit saved between push and pull is not overwritten by the pull',
      () async {
        await server.start();
        final a = await _Device('${dir.path}/a.db', port).boot();
        final b = await _Device('${dir.path}/b.db', port).boot();
        final id = (await a.academic.load()).courses.first.id;
        await a.renameCourse(id, 'A trên server');
        expect(await a.sync.syncNow(), SyncOutcome.ok);

        final raced = AcademicSyncService(
          store: b.store,
          academic: b.academic,
          transport: _InterceptingTransport(
            HttpSyncTransport(
              baseUri: Uri.parse('http://127.0.0.1:$port'),
              idToken: () async => 'test:teacher-1',
            ),
            () => b.renameCourse(id, 'B vừa lưu'),
          ),
          idleInterval: const Duration(hours: 1),
        );
        expect(await raced.syncNow(), SyncOutcome.ok);
        expect(await b.courseName(id), 'B vừa lưu');
        expect((await b.store.outbox()).map((o) => o.change.key), [
          'courses/$id',
        ]);
        raced.dispose();
        await a.shutdown();
        await b.shutdown();
      },
      skip: _Server.available ? false : 'server/.venv chưa có',
    );

    test('lost ack: re-sending the same ops is idempotent', () async {
      await server.start();
      final a = await _Device('${dir.path}/a.db', port).boot();
      final id = (await a.academic.load()).courses.first.id;
      await a.renameCourse(id, 'Một lần');
      final ops = await a.store.outbox();
      final transport = HttpSyncTransport(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        idToken: () async => 'test:teacher-1',
      );
      final body = {
        'device_id': await a.store.deviceId(),
        'ops': [for (final o in ops) o.toWire()],
      };
      final first = await transport.post('/sync/push', body);
      final again = await transport.post('/sync/push', body);
      transport.close();
      expect(
        ((first.body! as Map)['results'] as List).single['result'],
        'accepted',
      );
      expect(
        ((again.body! as Map)['results'] as List).single['result'],
        'duplicate',
      );
      // Client chưa nhận ack lần nào → gửi lại lần ba vẫn chỉ là duplicate.
      expect(await a.sync.syncNow(), SyncOutcome.ok);
      expect(await a.store.outboxCount(), 0);
      await a.shutdown();
    }, skip: _Server.available ? false : 'server/.venv chưa có');

    test('no token keeps the outbox and reports signedOut', () async {
      await server.start();
      final store = await OfflineAcademicStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/c.db',
      );
      final academic = FakeAcademicService(_DiskBundle(), persistence: store);
      final sync = AcademicSyncService(
        store: store,
        academic: academic,
        transport: HttpSyncTransport(
          baseUri: Uri.parse('http://127.0.0.1:$port'),
          idToken: () async => null,
        ),
        idleInterval: const Duration(hours: 1),
      );
      final snap = await academic.load();
      await academic.commit(
        AcademicSnapshot(snap.toJson()..['now'] = 1),
        snap.revision,
      );
      expect(await sync.syncNow(), SyncOutcome.signedOut);
      expect(await store.outboxCount(), 1);
      sync.dispose();
      await store.close();
    }, skip: _Server.available ? false : 'server/.venv chưa có');
  });
}
