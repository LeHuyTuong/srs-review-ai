/// Tests for the on-device session store (InMemory implementation) — the
/// behaviour the history view and snapshot restore depend on.
library;

import 'package:flutter_test/flutter_test.dart';
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
      SavedSession session({
        required String id,
        required String payload,
      }) => SavedSession(
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

    test('snapshot save / load / clear', () async {
      final store = InMemorySessionStore();
      expect(await store.loadSnapshot(), isNull);
      await store.saveSnapshot('{"units":[]}');
      expect(await store.loadSnapshot(), '{"units":[]}');
      await store.clearSnapshot();
      expect(await store.loadSnapshot(), isNull);
    });

    test('SavedSession json round trip', () {
      final session = SavedSession(
        id: 'id1',
        fileName: 'a.pdf',
        payloadJson: '{"x":1,"y":"quote \\" and \\n newline"}',
        createdAt: DateTime.parse('2026-01-02T03:04:05.000'),
      );
      final restored = SavedSession.decode(session.encode());
      expect(restored.id, session.id);
      expect(restored.payloadJson, session.payloadJson);
      expect(restored.createdAt, session.createdAt);
    });
  });
}
