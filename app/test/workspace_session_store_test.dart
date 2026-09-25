/// Tests for the on-device session store — the behaviour the history view,
/// the landing card's recent list and the workspace draft depend on.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_review_ai/data/services/session_store.dart';

void main() {
  group('InMemorySessionStore', () {
    test('save, list newest first, open, delete', () async {
      final store = InMemorySessionStore();
      await store.save(
        SavedSession(
          id: 'a',
          fileName: 'old.pdf',
          payloadJson: '{"units":[]}',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await store.save(
        SavedSession(
          id: 'b',
          fileName: 'new.pdf',
          payloadJson: '{"units":[]}',
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final list = await store.list();
      expect(list.map((s) => s.id), ['b', 'a']);

      final opened = await store.open('a');
      expect(opened?.fileName, 'old.pdf');
      expect(await store.open('missing'), isNull);

      await store.delete('a');
      expect((await store.list()).map((s) => s.id), ['b']);
    });

    test('keeps only the newest 30 sessions', () async {
      final store = InMemorySessionStore();
      for (var i = 0; i < 35; i++) {
        await store.save(
          SavedSession(
            id: 's$i',
            fileName: 'f.pdf',
            payloadJson: '{}',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }
      final list = await store.list();
      expect(list, hasLength(30));
      expect(list.first.id, 's34'); // newest kept
      expect(list.any((s) => s.id == 's0'), isFalse); // oldest dropped
    });

    test('re-saving the same id replaces instead of duplicating', () async {
      final store = InMemorySessionStore();
      SavedSession session({required String id, required String payload}) =>
          SavedSession(
            id: id,
            fileName: 'f.pdf',
            payloadJson: payload,
            createdAt: DateTime(2026, 1, 1),
          );
      await store.save(session(id: 'x', payload: 'one'));
      await store.save(session(id: 'x', payload: 'two'));
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.single.payloadJson, 'two');
    });

    test('draft save / load', () async {
      final store = InMemorySessionStore();
      expect(await store.loadDraft(), isNull);
      await store.saveDraft('{"projectName":"Đợt 1"}');
      expect(await store.loadDraft(), '{"projectName":"Đợt 1"}');
    });

    test('listRecent returns only the newest rows asked for', () async {
      final store = InMemorySessionStore();
      for (var i = 0; i < 5; i++) {
        await store.save(
          SavedSession(
            id: 's$i',
            fileName: 'f.pdf',
            payloadJson: '{}',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }

      expect((await store.listRecent(2)).map((s) => s.id), ['s4', 's3']);
      expect(await store.listRecent(0), isEmpty);
      expect((await store.listRecent(99)).map((s) => s.id), [
        's4',
        's3',
        's2',
        's1',
        's0',
      ]);
    });

    test('SavedSession json round trip', () {
      final session = SavedSession(
        id: 'id1',
        fileName: 'a.pdf',
        payloadJson: '{"x":1,"y":"quote \\" and \\n newline"}',
        createdAt: DateTime.parse('2026-01-02T03:04:05.000'),
        fingerprint: 'deadbeef',
        parserVersion: '1.0.0',
        projectName: 'Đợt 1 — OTES',
      );
      final restored = SavedSession.decode(session.encode());
      expect(restored.id, session.id);
      expect(restored.payloadJson, session.payloadJson);
      expect(restored.createdAt, session.createdAt);
      expect(restored.fingerprint, 'deadbeef');
      expect(restored.parserVersion, '1.0.0');
      expect(restored.projectName, 'Đợt 1 — OTES');
    });

    test('rows written before fingerprinting read back as unverifiable', () {
      // A hand-written row with no fingerprint/parserVersion keys — exactly
      // what older builds persisted — must decode without throwing and leave
      // both fields '' so the parser gate treats it as always-openable.
      final legacy = SavedSession.decode(
        '{"id":"old","fileName":"a.pdf","payloadJson":"{}",'
        '"createdAt":"2026-01-02T03:04:05.000"}',
      );
      expect(legacy.fingerprint, isEmpty);
      expect(legacy.parserVersion, isEmpty);
      // Same rule for the project bucket: rows written before it existed must
      // read back as '' and let the History grouping fall back to the payload.
      expect(legacy.projectName, isEmpty);
    });
  });

  group('SharedPreferencesSessionStore', () {
    test('wrongly-shaped rows do not take the whole history down', () async {
      // The read used to catch only FormatException. A row whose JSON parses
      // but is wrongly shaped (a bare number where the map belongs, a missing
      // required key) throws TypeError instead — the whole list() failed and
      // the history view showed "Could not load history" although every other
      // row was fine.
      final good = SavedSession(
        id: 'ok',
        fileName: 'a.pdf',
        payloadJson: '{"units":[]}',
        createdAt: DateTime(2026, 1, 1),
      );
      SharedPreferences.setMockInitialValues({
        'srs.workspace.sessions': <String>[
          'not json at all', // FormatException
          '5', // valid JSON, not a map
          '{"id": 5, "fileName": "b.pdf"}', // wrong field type
          '{"fileName": "c.pdf"}', // missing required keys
          good.encode(),
        ],
      });
      final store = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );

      final sessions = await store.list();
      expect(sessions.map((s) => s.id), ['ok']);
      expect((await store.open('ok'))?.fileName, 'a.pdf');
    });

    // Key names are literals on purpose: the store keeps them private, and a
    // rename that breaks recovery must break these tests loudly.
    const slotA = 'srs.workspace.sessions';
    const slotB = 'srs.workspace.sessions.b';
    const snapshotKey = 'srs.workspace.snapshot';
    const snapshotMirror = 'srs.workspace.snapshot.b';

    SavedSession session(String id, DateTime createdAt) => SavedSession(
      id: id,
      fileName: '$id.pdf',
      payloadJson: '{"units":[]}',
      createdAt: createdAt,
    );

    Future<SharedPreferencesSessionStore> freshStore() async {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );
    }

    test('a torn replica is recovered from its mirror and repaired', () async {
      final store = await freshStore();
      final prefs = await SharedPreferences.getInstance();
      await store.save(session('a', DateTime(2026, 1, 1)));
      await store.save(session('b', DateTime(2026, 1, 2)));
      expect((await store.list()).map((s) => s.id), ['b', 'a']);

      // The app died in the middle of writing replica A: the key holds a
      // fragment that cannot parse.
      await prefs.setString(slotA, '{"generation":9,"sessions":[');

      final recovered = await store.list();
      expect(
        recovered.map((s) => s.id),
        ['b', 'a'],
        reason: 'the mirror must keep the history readable',
      );

      // The damaged replica was re-published, so the next read finds two good
      // copies again — the window with a single copy is closed here.
      final healed = prefs.getString(slotA);
      expect(healed, isNotNull);
      expect(
        (jsonDecode(healed!) as Map<String, dynamic>)['sessions'],
        hasLength(2),
      );
      expect((await store.list()).map((s) => s.id), ['b', 'a']);
    });

    test(
      'a generation whose rows all rotted falls back to the mirror',
      () async {
        final store = await freshStore();
        final prefs = await SharedPreferences.getInstance();
        await store.save(session('a', DateTime(2026, 1, 1)));

        // Replica A still parses and claims a newer generation, but none of its
        // rows decode — an emptied history would have declared zero rows, so
        // this must not be read as "the user deleted everything".
        await prefs.setString(
          slotA,
          jsonEncode({
            'generation': 9,
            'writtenAt': '2026-01-01T00:00:00.000',
            'sessions': ['not json', '{"id": 5}'],
          }),
        );

        expect((await store.list()).map((s) => s.id), ['a']);
      },
    );

    test('a legacy List<String> history is upgraded, not lost', () async {
      SharedPreferences.setMockInitialValues({
        slotA: <String>[session('old', DateTime(2026, 1, 1)).encode()],
      });
      final store = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );

      await store.save(session('new', DateTime(2026, 1, 2)));

      expect((await store.list()).map((s) => s.id), ['new', 'old']);
      // Both replicas now hold the envelope, the legacy list is gone.
      // `getString`/`getStringList` cast internally and throw on the other
      // type — read the neutral value, then check the shape.
      final prefs = await SharedPreferences.getInstance();
      final upgradedA = prefs.get(slotA);
      final upgradedB = prefs.get(slotB);
      expect(upgradedA, isA<String>());
      expect(upgradedB, isA<String>());
      expect(
        (jsonDecode(upgradedA! as String) as Map<String, dynamic>)['sessions'],
        hasLength(2),
      );
    });

    test('a delete-all is not undone by a later torn replica', () async {
      final store = await freshStore();
      final prefs = await SharedPreferences.getInstance();
      await store.save(session('a', DateTime(2026, 1, 1)));
      await store.delete('a');
      expect(await store.list(), isEmpty);

      await prefs.setString(slotA, '{torn');
      expect(
        await store.list(),
        isEmpty,
        reason: 'the mirror also holds the empty generation — no resurrection',
      );
    });

    test('the draft round-trips through the legacy store', () async {
      final store = await freshStore();
      await store.saveDraft('{"projectName":"Đợt 1"}');

      expect(await store.loadDraft(), '{"projectName":"Đợt 1"}');

      // A second instance over the same storage sees the same draft: this
      // store is the fallback when the database cannot open, and it still has
      // to survive a restart.
      final reopened = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );
      expect(await reopened.loadDraft(), '{"projectName":"Đợt 1"}');
    });

    test('the old workspace snapshot key is never served as a draft', () async {
      // Builds that predate the draft kept a whole workspace (units + result,
      // ~1 MB on OTES) under this key. The draft lives at a different key on
      // purpose: those two shapes must never be confused, and nothing reads
      // the old one any more.
      SharedPreferences.setMockInitialValues({
        snapshotKey: '{"units":[{"key":"uc-1"}],"pageTexts":["…"]}',
        snapshotMirror: '{"units":[],"result":{"score":9}}',
      });
      final store = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );

      expect(await store.loadDraft(), isNull);
      // Left untouched on disk so an older build reinstalled over this one
      // still finds it; what stopped is reading it, not keeping it.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(snapshotKey), isNotNull);
    });

    test('the draft is not mirrored and refuses to throw on read', () async {
      // The mirror existed for the 1 MB snapshot; a few hundred bytes the user
      // can retype do not need a second copy, and any read failure must fall
      // back to "no draft" rather than break startup.
      SharedPreferences.setMockInitialValues({
        'srs.workspace.draft': 5, // wrong type on purpose
      });
      final store = SharedPreferencesSessionStore(
        await SharedPreferences.getInstance(),
      );

      expect(await store.loadDraft(), isNull);
    });

    // The refusal branch of the write (platform answers `false`) cannot be
    // exercised here: the mock platform store always accepts writes, and
    // faking it would need `shared_preferences_platform_interface` as a direct
    // dependency. The exception type it throws is asserted end-to-end in
    // workspace_view_model_test.dart ('a refused history write is reported').
  });
}
