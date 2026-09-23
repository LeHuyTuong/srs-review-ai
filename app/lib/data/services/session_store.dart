/// On-device review history — the Flutter answer to the brief's localStorage
/// + Drizzle/PostgreSQL history.
///
/// The brief saves sessions either to the browser (offline mode) or to its
/// Next.js server. This app is offline-first, so sessions live on the device
/// behind this tiny interface; the shared_preferences implementation keeps the
/// 30-session cap the brief's server endpoint uses. Payloads are opaque JSON
/// strings — serialization lives with the feature models, not here.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedSession {
  const SavedSession({
    required this.id,
    required this.fileName,
    required this.payloadJson,
    required this.createdAt,
    this.fingerprint = '',
    this.parserVersion = '',
    this.projectName = '',
  });

  factory SavedSession.fromJson(Map<String, dynamic> json) => SavedSession(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    payloadJson: json['payloadJson'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    // Rows written before fingerprinting existed carry no such key; they read
    // back as unverifiable (''), not broken.
    fingerprint: json['fingerprint'] as String? ?? '',
    parserVersion: json['parserVersion'] as String? ?? '',
    // Denormalized copy of the payload's `projectName`: the History tab groups
    // rows by it WITHOUT decoding a multi-megabyte payload per row per build,
    // and a payload too damaged to decode still lands in its own bucket
    // instead of "unassigned". Rows written before this field existed read
    // back as '' and fall back to the payload (see groupSessionsByProject).
    projectName: (json['projectName'] as String?)?.trim() ?? '',
  );

  static SavedSession decode(String raw) =>
      SavedSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  final String id;
  final String fileName;
  final String payloadJson;
  final DateTime createdAt;

  /// sha256 of the parsed document text the review was produced from, plus
  /// the parser version that produced it — stored separately from each other
  /// because the same text under a different parser may key units
  /// differently. '' on rows written before versioning existed.
  final String fingerprint;
  final String parserVersion;

  /// Step-1 project container this run belongs to, '' when it was produced
  /// outside any project.
  final String projectName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'payloadJson': payloadJson,
    'createdAt': createdAt.toIso8601String(),
    'fingerprint': fingerprint,
    'parserVersion': parserVersion,
    'projectName': projectName,
  };

  String encode() => jsonEncode(toJson());
}

/// A write the platform refused: storage full, quota exhausted, or a web
/// origin that forbids persistent storage. Callers must surface it — a
/// history that silently drops a finished (paid-for) review is worse than an
/// error banner the user can act on.
class SessionStoreException implements Exception {
  const SessionStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class SessionStore {
  /// Newest first, capped at [maxSessions].
  Future<List<SavedSession>> list();

  /// The newest [limit] rows, and only those — the landing screen's
  /// "continue where you left off" card must not pull 30 multi-megabyte
  /// payloads into memory to show three titles. For the same reason it is not
  /// a `list()` call plus `take()` in the database-backed store, the one that
  /// actually serves devices.
  Future<List<SavedSession>> listRecent(int limit);

  Future<void> save(SavedSession session);

  Future<SavedSession?> open(String id);

  Future<void> delete(String id);

  /// The small "where I left off" record: workflow step 1 (project container)
  /// and step 2 (the declaration), and nothing else.
  ///
  /// Deliberately NOT the whole workspace: since 2026-09-23 the app never
  /// reopens a previous session by itself (that is what History → openSession
  /// is for), so units, findings and triage have no reader here. Writing them
  /// anyway was measured I/O with no consumer; the draft exists so work the
  /// user typed but never ran is not thrown away by a restart.
  Future<String?> loadDraft();

  Future<void> saveDraft(String draftJson);
}

class InMemorySessionStore implements SessionStore {
  final List<SavedSession> _sessions = [];
  String? _draft;

  static const int maxSessions = 30;

  @override
  Future<List<SavedSession>> list() async =>
      [..._sessions]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<SavedSession>> listRecent(int limit) async =>
      (await list()).take(limit).toList(growable: false);

  @override
  Future<void> save(SavedSession session) async {
    _sessions.removeWhere((s) => s.id == session.id);
    _sessions.add(session);
    if (_sessions.length > maxSessions) {
      _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _sessions.removeRange(maxSessions, _sessions.length);
    }
  }

  @override
  Future<SavedSession?> open(String id) async {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async =>
      _sessions.removeWhere((s) => s.id == id);

  @override
  Future<String?> loadDraft() async => _draft;

  @override
  Future<void> saveDraft(String draftJson) async => _draft = draftJson;
}

/// One replica's decoded content plus the generation it was stamped with.
class _SessionSlot {
  const _SessionSlot({
    required this.generation,
    required this.sessions,
    required this.declaredRows,
  });

  final int generation;
  final List<SavedSession> sessions;

  /// Rows the replica declared, decodable or not. A replica that declared
  /// rows but decoded none is damaged — an intentionally emptied history
  /// writes a generation with an empty `sessions` array, so "declared 0" and
  /// "declared rows, none usable" are different states.
  final int declaredRows;

  bool get usable => declaredRows == 0 || sessions.isNotEmpty;
}

/// Two mirrored replicas + a generation stamp, so the history is never a
/// single copy that one bad write can erase.
///
/// Every save writes the SAME envelope (generation, timestamp, encoded rows)
/// to both keys. Every read takes the replica with the highest generation that
/// still parses and re-publishes it into the damaged one. What that buys on a
/// real device:
///
///   * a write cut half-way (app killed, storage full, blocked web origin)
///     can only damage the replica being written — the other still holds the
///     same generation, so the fallback is the SAME history, not an empty one;
///   * an envelope that parses but whose rows all rotted counts as damaged
///     and falls back (see [_SessionSlot.usable]);
///   * repairing is best-effort: a read never fails because the repair write
///     was refused.
///
/// Cost: both replicas hold the newest generation, so the history occupies
/// ~2× its own size (measured on the OTES run: 1.1 MB list → ~2.2 MB). On the
/// web build localStorage is the wall; a save both replicas refused surfaces
/// as [SessionStoreException] instead of a silent loss.
class SharedPreferencesSessionStore implements SessionStore {
  SharedPreferencesSessionStore(this._prefs);

  final SharedPreferences _prefs;

  /// Replica A doubles as the key older builds used for the plain
  /// `List<String>` of rows — that legacy value is read as generation 0.
  static const String _slotAKey = 'srs.workspace.sessions';
  static const String _slotBKey = 'srs.workspace.sessions.b';

  /// The step-1/step-2 draft. A key older builds never wrote, so a legacy
  /// whole-workspace snapshot (`srs.workspace.snapshot`, left untouched on
  /// disk) can never be mistaken for one.
  static const String _draftKey = 'srs.workspace.draft';

  static const int maxSessions = 30;

  /// Envelopes are written with `generation` first, so ordering two replicas
  /// costs a head match instead of decoding a multi-megabyte list twice.
  static final RegExp _generationHead = RegExp(r'^\{"generation":(\d+)');

  static String _encodeGeneration(
    int generation,
    List<SavedSession> sessions,
  ) => jsonEncode({
    'generation': generation,
    'writtenAt': DateTime.now().toIso8601String(),
    'sessions': sessions
        .take(maxSessions)
        .map((s) => s.encode())
        .toList(growable: false),
  });

  /// The raw value of a key. `getString`/`getStringList` cast internally and
  /// THROW when the key holds the other type — which is exactly the state a
  /// build older than this scheme leaves behind (a `List<String>` under
  /// [_slotAKey]), so every read goes through the type-neutral getter.
  Object? _stored(String key) => _prefs.get(key);

  /// Generation a replica holds, without decoding its rows: -1 = nothing
  /// stored, 0 = the legacy `List<String>` (older than any envelope).
  int _storedGeneration(String key) {
    final stored = _stored(key);
    if (stored is List) return 0;
    if (stored is! String) return -1;
    final head = _generationHead.firstMatch(stored);
    if (head != null) return int.parse(head.group(1)!);
    // Envelope in an unexpected shape: pay for a decode rather than treat a
    // real generation as absent.
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return (json['generation'] as int?) ?? 0;
    } on Object {
      return -1;
    }
  }

  /// One replica, tolerating every shape the keys have ever held: the
  /// generation envelope this store writes, or the legacy `List<String>`.
  /// Null when the key holds nothing or the envelope does not parse — the
  /// caller then falls back to the other replica.
  _SessionSlot? _readSlot(String key) {
    final stored = _stored(key);
    if (stored is String) {
      try {
        final json = jsonDecode(stored) as Map<String, dynamic>;
        final rawRows =
            (json['sessions'] as List<dynamic>? ?? const <dynamic>[]);
        return _SessionSlot(
          generation: (json['generation'] as int?) ?? 0,
          sessions: _decodeRows(rawRows.whereType<String>()),
          declaredRows: rawRows.length,
        );
      } on Object {
        // A half-written envelope is damaged, not authoritative.
        return null;
      }
    }
    if (stored is List) {
      return _SessionSlot(
        generation: 0,
        sessions: _decodeRows(stored.whereType<String>()),
        declaredRows: stored.length,
      );
    }
    return null;
  }

  List<SavedSession> _decodeRows(Iterable<String> rows) {
    final sessions = <SavedSession>[];
    for (final entry in rows) {
      try {
        sessions.add(SavedSession.decode(entry));
      } on Object {
        // A corrupt row must not take the history down. `on FormatException`
        // was not enough: a row whose JSON parses but is wrongly shaped
        // (`{"id": 5}`) throws TypeError from the casts, which sailed past the
        // catch and made list() fail — the history view then showed
        // "Could not load history" instead of the rows that were fine, and the
        // next save rewrote the list from a read that never completed.
        continue;
      }
    }
    return sessions;
  }

  List<SavedSession> _sorted(Iterable<SavedSession> sessions) =>
      [...sessions]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int _nextGeneration() {
    final a = _storedGeneration(_slotAKey);
    final b = _storedGeneration(_slotBKey);
    final newest = a > b ? a : b;
    return newest < 0 ? 1 : newest + 1;
  }

  /// Writes one new generation to BOTH replicas. Succeeds when at least one
  /// took the write (the other is repaired on the next read) and throws only
  /// when both were refused — the one case where the caller really did lose
  /// the data.
  Future<void> _publish(List<SavedSession> sessions) async {
    final payload = _encodeGeneration(_nextGeneration(), sessions);
    final writtenA = await _prefs.setString(_slotAKey, payload);
    final writtenB = await _prefs.setString(_slotBKey, payload);
    if (!writtenA && !writtenB) {
      throw const SessionStoreException(
        'The device refused to store the review history in either copy — '
        'storage may be full or blocked.',
      );
    }
  }

  /// Newest generation first. The older replica is only read when the newer
  /// one is damaged; after such a fallback it is re-published so the next read
  /// finds two good copies again.
  Future<List<SavedSession>> _readAll() async {
    final aGeneration = _storedGeneration(_slotAKey);
    final bGeneration = _storedGeneration(_slotBKey);
    final keysByRecency = aGeneration >= bGeneration
        ? const [_slotAKey, _slotBKey]
        : const [_slotBKey, _slotAKey];

    _SessionSlot? active;
    String? activeKey;
    for (final key in keysByRecency) {
      final slot = _readSlot(key);
      if (slot != null && slot.usable) {
        active = slot;
        activeKey = key;
        break;
      }
    }
    // Always a fresh mutable list: callers (`save`, `delete`) edit it in
    // place, and a const empty list made the first save of a fresh install
    // throw "Cannot remove from an unmodifiable list".
    if (active == null || activeKey == null) return <SavedSession>[];

    final otherKey = activeKey == _slotAKey ? _slotBKey : _slotAKey;
    if (_storedGeneration(otherKey) != active.generation) {
      await _heal(otherKey, active.sessions);
    }
    return _sorted(active.sessions);
  }

  /// Best-effort repair of the damaged replica: the read already holds the
  /// data, and failing to write it back must not fail the read — the next save
  /// publishes both replicas anyway.
  Future<void> _heal(String targetKey, List<SavedSession> sessions) async {
    try {
      await _prefs.setString(
        targetKey,
        _encodeGeneration(_nextGeneration(), sessions),
      );
    } on Object {
      // Repair is a bonus, never a requirement of reading.
    }
  }

  @override
  Future<List<SavedSession>> list() => _readAll();

  @override
  Future<List<SavedSession>> listRecent(int limit) async =>
      (await _readAll()).take(limit).toList(growable: false);

  @override
  Future<void> save(SavedSession session) async {
    final sessions = await _readAll()
      ..removeWhere((s) => s.id == session.id)
      ..insert(0, session);
    await _publish(sessions);
  }

  @override
  Future<SavedSession?> open(String id) async {
    for (final session in await _readAll()) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final sessions = await _readAll()
      ..removeWhere((s) => s.id == id);
    await _publish(sessions);
  }

  @override
  Future<String?> loadDraft() async {
    final stored = _stored(_draftKey);
    return stored is String && stored.isNotEmpty ? stored : null;
  }

  @override
  Future<void> saveDraft(String draftJson) async {
    // No mirror: a draft is a few hundred bytes the user can retype, unlike
    // the 1 MB snapshot this key replaced. A refused write still surfaces so
    // the caller can decide, matching the history writes above.
    final written = await _prefs.setString(_draftKey, draftJson);
    if (!written) {
      throw const SessionStoreException(
        'The device refused to store the workspace draft — the review itself '
        'is unaffected.',
      );
    }
  }
}
