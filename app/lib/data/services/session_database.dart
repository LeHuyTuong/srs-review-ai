/// History in a real database, not one JSON blob behind two mirrored keys.
///
/// The `shared_preferences` store kept everything in a single value: every save
/// re-encoded the whole history (measured 1.1 MB on the OTES run), wrote it
/// twice, and had to re-read and re-sort the lot to add one session. That is
/// what a database is for, so this is the primary store now:
///
///   * one record per session, keyed by its id — saving one session writes one
///     small record, whatever the history weighs;
///   * the workspace DRAFT (step-1 project + step-2 declaration) lives beside
///     it in its own record, so it no longer shares a value with a 30-session
///     list — and it is small, because since 2026-09-23 the app no longer
///     reopens a whole previous workspace by itself;
///   * the 30-session cap is enforced by deleting the coldest RECORDS instead of
///     rewriting a list that silently drops them.
///
/// Engine: `sembast` — a single-file embedded database, 100% Dart. SQLite would
/// be the reflexive answer, but every SQLite route into Flutter needs native
/// code (`sqflite_common_ffi` + a per-platform library, plus wasm assets for
/// web), and this repo has already paid for that lesson: `pdfx`'s native plugin
/// is unusable in every host test runner (see AGENTS.md), and CI runs
/// `flutter test` on a bare ubuntu image. A pure-Dart database is fully
/// exercised by the suite, on the host, with no setup — which is worth more here
/// than SQL syntax.
///
/// This class implements the same [SessionStore] interface the workspace view
/// model already talks to, so nothing above it changed.
library;

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_database_platform.dart';
import 'session_store.dart';

/// Opens the history store, preferring the database.
///
/// The fallback is not a formality: a browser with IndexedDB blocked, a device
/// whose support directory cannot be created, or a plain `flutter test` run
/// (where `path_provider` has no platform implementation) all land on the
/// `shared_preferences` store the app used before. Losing the database must
/// never mean losing the history, so the old store's data is imported into the
/// new one on first launch — and never deleted from the old one.
Future<SessionStore> openSessionStore({
  required SharedPreferences prefs,
  DatabaseFactory? factory,
  String? path,
}) async {
  final legacy = SharedPreferencesSessionStore(prefs);
  SessionDatabaseStore? database;
  try {
    database = factory != null
        ? await SessionDatabaseStore.openAt(path ?? 'srs_review_ai.db', factory)
        : await SessionDatabaseStore.openPlatform();
    await database.importLegacy(legacy);
    return database;
  } on Object catch (error) {
    debugPrint(
      'session database unavailable ($error); using shared_preferences',
    );
    // Close what was opened: a half-usable handle left behind would keep the
    // file locked for nothing, since this run is not going to use it.
    try {
      await database?.close();
    } on Object {
      // Closing is best-effort here; the store is being abandoned anyway.
    }
    return legacy;
  }
}

class SessionDatabaseStore implements SessionStore {
  SessionDatabaseStore._(this._db);

  /// Same cap the brief's server endpoint uses, and the one the history view
  /// advertises ("up to 30 sessions").
  static const int maxSessions = 30;

  static final StoreRef<String, Map<String, Object?>> _sessions =
      stringMapStoreFactory.store('sessions');
  static final StoreRef<String, String> _meta = StoreRef<String, String>(
    'meta',
  );

  static const String _createdAtField = 'createdAt';
  static const String _draftRecord = 'workspaceDraft';
  static const String _legacyImportRecord = 'legacyImportedAt';

  final Database _db;

  /// Opens the database at [path] (created if missing) with an explicit
  /// [factory]. Named `openAt` because [SessionStore.open] — "read one saved
  /// session" — already owns the word `open` in this class.
  static Future<SessionDatabaseStore> openAt(
    String path,
    DatabaseFactory factory,
  ) async => SessionDatabaseStore._(await factory.openDatabase(path));

  /// Opens the database wherever this platform keeps app files.
  static Future<SessionDatabaseStore> openPlatform() async =>
      SessionDatabaseStore._(await openPlatformDatabase());

  /// An in-memory database, for tests and for the degraded path.
  static Future<SessionDatabaseStore> memory() async => SessionDatabaseStore._(
    await databaseFactoryMemory.openDatabase('srs_review_ai.memory'),
  );

  Future<void> close() => _db.close();

  /// Records currently stored. Exposed for tests and diagnostics ("is the
  /// history really in the database?") rather than for feature code.
  Future<int> count() => _sessions.count(_db);

  /// Test hook: writes a record that bypasses the model, so a row that no
  /// longer matches it can be simulated. Schema drift is a real event here — a
  /// wrongly shaped row is exactly what used to take the old store's whole list
  /// down — and it has to be reproducible without hand-editing the file.
  @visibleForTesting
  Future<void> putRawRecord(String id, Map<String, Object?> json) =>
      _sessions.record(id).put(_db, json);

  // ------------------------------------------------------------------ //
  // SessionStore
  // ------------------------------------------------------------------ //

  @override
  Future<List<SavedSession>> list() async {
    final snapshots = await _sessions.find(
      _db,
      finder: Finder(sortOrders: [SortOrder(_createdAtField, false)]),
    );
    final sessions = <SavedSession>[];
    for (final snapshot in snapshots) {
      try {
        sessions.add(
          SavedSession.fromJson(Map<String, dynamic>.from(snapshot.value)),
        );
      } on Object {
        // One row that no longer decodes must not take the history down: the
        // same rule the mirrored-keys store learned the hard way (a `TypeError`
        // from a wrongly shaped row used to fail the whole list).
        continue;
      }
    }
    return sessions;
  }

  @override
  Future<void> save(SavedSession session) async {
    await _guard(() async {
      await _sessions.record(session.id).put(_db, session.toJson());
      await _prune();
    });
  }

  @override
  Future<SavedSession?> open(String id) async {
    final value = await _sessions.record(id).get(_db);
    if (value == null) return null;
    try {
      return SavedSession.fromJson(Map<String, dynamic>.from(value));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> delete(String id) async {
    await _guard(() => _sessions.record(id).delete(_db));
  }

  @override
  Future<List<SavedSession>> listRecent(int limit) async {
    if (limit <= 0) return const [];
    final snapshots = await _sessions.find(
      _db,
      // The finder stops at the requested rows: the landing card asks for
      // three titles and must not read 27 more payloads to do it.
      finder: Finder(
        sortOrders: [SortOrder(_createdAtField, false)],
        limit: limit,
      ),
    );
    final sessions = <SavedSession>[];
    for (final snapshot in snapshots) {
      try {
        sessions.add(
          SavedSession.fromJson(Map<String, dynamic>.from(snapshot.value)),
        );
      } on Object {
        // Same rule as list(): a row that no longer decodes is skipped, never
        // allowed to take the card down.
        continue;
      }
    }
    return sessions;
  }

  @override
  Future<String?> loadDraft() async {
    final value = await _meta.record(_draftRecord).get(_db);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> saveDraft(String draftJson) async {
    await _guard(() => _meta.record(_draftRecord).put(_db, draftJson));
  }

  // ------------------------------------------------------------------ //
  // Migration + internals
  // ------------------------------------------------------------------ //

  /// Moves whatever the old store holds into the database — once.
  ///
  /// The legacy store is READ, never cleared: a device that downgrades to an
  /// older build still finds its history where it always was, and the import is
  /// idempotent because the flag is written either way. Rows that cannot be
  /// decoded are skipped by `list()` itself, so a damaged legacy copy imports
  /// exactly the rows that were still good.
  ///
  /// Sessions only. The old store also kept a whole-workspace snapshot
  /// (`srs.workspace.snapshot`) so a restart resumed the last session; since
  /// 2026-09-23 nothing reads one (History → openSession is the way back), so
  /// importing it would write a megabyte no code can use. What the new build
  /// keeps from the old one is the paid-for history.
  Future<bool> importLegacy(SessionStore legacy) async {
    if (await _meta.record(_legacyImportRecord).get(_db) != null) return false;
    try {
      final existing = await count();
      if (existing == 0) {
        for (final session in await legacy.list()) {
          await save(session);
        }
      }
    } on Object {
      // A failed import must not cost the user the app: the next launch retries
      // (the flag is only written after this block).
      return false;
    }
    await _guard(
      () async => _meta
          .record(_legacyImportRecord)
          .put(_db, DateTime.now().toIso8601String()),
    );
    return true;
  }

  /// Enforces [maxSessions] by deleting whole records.
  ///
  /// The old store could only truncate the list it was about to write, which
  /// meant a session could be dropped by a write that failed halfway. Deleting
  /// explicit records keeps the cap honest: what disappears is decided here,
  /// not by whatever the platform did with a 1 MB string.
  Future<void> _prune() async {
    final total = await _sessions.count(_db);
    final excess = total - maxSessions;
    if (excess <= 0) return;
    final oldest = await _sessions.find(
      _db,
      finder: Finder(
        sortOrders: [SortOrder(_createdAtField, true)],
        limit: excess,
      ),
    );
    await _sessions.records(oldest.map((s) => s.key)).delete(_db);
  }

  /// Turns any storage failure into the one exception the UI already handles.
  ///
  /// A history that silently drops a finished (paid-for) review is worse than
  /// an error banner, so nothing here is swallowed.
  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } on SessionStoreException {
      rethrow;
    } on Object catch (error) {
      throw SessionStoreException(
        'The device refused to store the review history: $error',
      );
    }
  }
}
