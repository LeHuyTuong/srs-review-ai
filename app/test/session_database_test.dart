/// The database-backed session store.
///
/// These run against a real file in a temp directory (`databaseFactoryIo`), not
/// a mock: the whole reason for choosing a pure-Dart database was that the suite
/// can exercise the real thing on the host and in CI, with no native library and
/// no plugin channel. The one thing that cannot be tested here is
/// `path_provider` (a plugin), which is why the store takes its path as an
/// argument and the provider is only reached through the fallback test below.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_review_ai/data/services/session_database.dart';
import 'package:srs_review_ai/data/services/session_store.dart';

SavedSession _session(String id, {int minute = 0, String fileName = 'srs.pdf'}) =>
    SavedSession(
      id: id,
      fileName: fileName,
      payloadJson: jsonEncode({'units': <String>[], 'id': id}),
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: minute)),
      fingerprint: 'fp-$id',
      parserVersion: '1.4.2',
    );

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('srs-session-db-test-');
    path = '${dir.path}/sessions.db';
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<SessionDatabaseStore> open() =>
      SessionDatabaseStore.openAt(path, databaseFactoryIo);

  group('SessionDatabaseStore', () {
    test('save, list newest first, open, delete', () async {
      final store = await open();
      addTearDown(store.close);
      await store.save(_session('a'));
      await store.save(_session('b', minute: 5));

      expect((await store.list()).map((s) => s.id), ['b', 'a']);
      expect((await store.open('a'))!.fileName, 'srs.pdf');
      expect((await store.open('a'))!.fingerprint, 'fp-a');
      expect(await store.open('missing'), isNull);

      await store.delete('a');
      expect((await store.list()).map((s) => s.id), ['b']);
      await store.delete('a'); // deleting twice is not an error
    });

    test('re-saving an id updates the row instead of duplicating it', () async {
      final store = await open();
      addTearDown(store.close);
      await store.save(_session('a', fileName: 'first.pdf'));
      await store.save(_session('a', fileName: 'second.pdf'));

      expect(await store.count(), 1);
      expect((await store.open('a'))!.fileName, 'second.pdf');
    });

    test('the history survives closing and reopening the database', () async {
      final first = await open();
      await first.save(_session('a', minute: 3));
      await first.saveSnapshot('{"units":[]}');
      await first.close();

      final second = await open();
      addTearDown(second.close);
      expect((await second.list()).map((s) => s.id), ['a']);
      expect(await second.loadSnapshot(), '{"units":[]}');
    });

    test('keeps only the newest 30 sessions, by deleting records', () async {
      final store = await open();
      addTearDown(store.close);
      for (var index = 0; index < 35; index++) {
        await store.save(_session('s$index', minute: index));
      }

      final list = await store.list();
      expect(list, hasLength(SessionDatabaseStore.maxSessions));
      expect(list.first.id, 's34');
      expect(list.any((s) => s.id == 's0'), isFalse);
      expect(await store.count(), SessionDatabaseStore.maxSessions);
    });

    test('a row that no longer matches the model does not take the list down', () async {
      final store = await open();
      addTearDown(store.close);
      await store.save(_session('good'));
      await store.putRawRecord('drifted', {'id': 5, 'createdAt': 12345});
      await store.putRawRecord('halfWritten', {'id': 'x'});

      final list = await store.list();
      expect(list.map((s) => s.id), ['good']);
      expect(await store.open('drifted'), isNull);
    });

    test('snapshot round-trip, replace, and clear', () async {
      final store = await open();
      addTearDown(store.close);
      expect(await store.loadSnapshot(), isNull);

      await store.saveSnapshot('{"a":1}');
      expect(await store.loadSnapshot(), '{"a":1}');

      await store.saveSnapshot('{"a":2}');
      expect(await store.loadSnapshot(), '{"a":2}');

      await store.clearSnapshot();
      expect(await store.loadSnapshot(), isNull);
    });

    test('an empty snapshot value is not mistaken for a real one', () async {
      final store = await open();
      addTearDown(store.close);
      await store.putRawRecord('placeholder', const {});
      await store.saveSnapshot('');
      expect(await store.loadSnapshot(), isNull);
    });
  });

  group('migration from shared_preferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('imports the legacy history and snapshot exactly once', () async {
      final legacy = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );
      await legacy.save(_session('old-1', minute: 1));
      await legacy.save(_session('old-2', minute: 2));
      await legacy.saveSnapshot('{"legacy":true}');

      final store = await open();
      addTearDown(store.close);
      expect(await store.importLegacy(legacy), isTrue);

      expect((await store.list()).map((s) => s.id), ['old-2', 'old-1']);
      expect(await store.loadSnapshot(), '{"legacy":true}');
      // The legacy copy is left alone: a downgrade still finds its history.
      expect((await legacy.list()).map((s) => s.id), ['old-2', 'old-1']);

      // Second launch: nothing is imported again, and a session the user
      // deleted does not come back from the old store.
      await store.delete('old-1');
      expect(await store.importLegacy(legacy), isFalse);
      expect((await store.list()).map((s) => s.id), ['old-2']);
    });

    test('leaves a database that already has sessions untouched', () async {
      final legacy = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );
      await legacy.save(_session('legacy'));

      final store = await open();
      addTearDown(store.close);
      await store.save(_session('database', minute: 9));

      await store.importLegacy(legacy);
      expect((await store.list()).map((s) => s.id), ['database']);
    });

    test('a refused import is retried on the next launch', () async {
      final legacy = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );
      await legacy.save(_session('legacy'));

      final store = await open();
      addTearDown(store.close);
      // A legacy store that throws stands in for unreadable old data: the flag
      // must NOT be written, or the history would be lost permanently.
      expect(await store.importLegacy(_ExplodingStore()), isFalse);

      expect(await store.importLegacy(legacy), isTrue);
      expect((await store.list()).map((s) => s.id), ['legacy']);
    });
  });

  group('openSessionStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('prefers the database when one can be opened', () async {
      final store = await openSessionStore(
        prefs: await SharedPreferences.getInstance(),
        factory: databaseFactoryIo,
        path: path,
      );
      addTearDown((store as SessionDatabaseStore).close);
      expect(store, isA<SessionDatabaseStore>());

      await store.save(_session('in-database'));
      final reopened = await SessionDatabaseStore.openAt(
        path,
        databaseFactoryIo,
      );
      addTearDown(reopened.close);
      expect((await reopened.list()).map((s) => s.id), ['in-database']);
    });

    test('falls back to shared_preferences when the database cannot open', () async {
      // A directory is not a database file: this is the shape of a device whose
      // support directory exists but is not writable.
      final store = await openSessionStore(
        prefs: await SharedPreferences.getInstance(),
        factory: databaseFactoryIo,
        path: dir.path,
      );

      expect(store, isA<SharedPreferencesSessionStore>());
      await store.save(_session('degraded'));
      expect((await store.list()).map((s) => s.id), ['degraded']);
    });
  });
}

/// A legacy store that cannot be read at all.
class _ExplodingStore implements SessionStore {
  @override
  Future<List<SavedSession>> list() async => throw StateError('unreadable');

  @override
  Future<SavedSession?> open(String id) async => throw StateError('unreadable');

  @override
  Future<void> save(SavedSession session) async => throw StateError('unreadable');

  @override
  Future<void> delete(String id) async => throw StateError('unreadable');

  @override
  Future<String?> loadSnapshot() async => throw StateError('unreadable');

  @override
  Future<void> saveSnapshot(String snapshotJson) async =>
      throw StateError('unreadable');

  @override
  Future<void> clearSnapshot() async => throw StateError('unreadable');
}
