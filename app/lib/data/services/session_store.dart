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

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'payloadJson': payloadJson,
    'createdAt': createdAt.toIso8601String(),
    'fingerprint': fingerprint,
    'parserVersion': parserVersion,
  };

  String encode() => jsonEncode(toJson());
}

abstract class SessionStore {
  /// Newest first, capped at [maxSessions].
  Future<List<SavedSession>> list();

  Future<void> save(SavedSession session);

  Future<SavedSession?> open(String id);

  Future<void> delete(String id);

  /// Whole-workspace snapshot (units + result) so a restart restores the
  /// brief's localStorage behaviour.
  Future<String?> loadSnapshot();

  Future<void> saveSnapshot(String snapshotJson);

  Future<void> clearSnapshot();
}

class InMemorySessionStore implements SessionStore {
  final List<SavedSession> _sessions = [];
  String? _snapshot;

  static const int maxSessions = 30;

  @override
  Future<List<SavedSession>> list() async =>
      [..._sessions]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
  Future<String?> loadSnapshot() async => _snapshot;

  @override
  Future<void> saveSnapshot(String snapshotJson) async =>
      _snapshot = snapshotJson;

  @override
  Future<void> clearSnapshot() async => _snapshot = null;
}

class SharedPreferencesSessionStore implements SessionStore {
  SharedPreferencesSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _sessionsKey = 'srs.workspace.sessions';
  static const String _snapshotKey = 'srs.workspace.snapshot';
  static const int maxSessions = 30;

  List<SavedSession> _readAll() {
    final raw = _prefs.getStringList(_sessionsKey) ?? const <String>[];
    final sessions = <SavedSession>[];
    for (final entry in raw) {
      try {
        sessions.add(SavedSession.decode(entry));
      } on FormatException {
        continue; // a corrupt entry must not take the history down
      }
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  Future<void> _writeAll(List<SavedSession> sessions) async {
    await _prefs.setStringList(
      _sessionsKey,
      sessions.take(maxSessions).map((s) => s.encode()).toList(growable: false),
    );
  }

  @override
  Future<List<SavedSession>> list() async => _readAll();

  @override
  Future<void> save(SavedSession session) async {
    final sessions = _readAll()
      ..removeWhere((s) => s.id == session.id)
      ..insert(0, session);
    await _writeAll(sessions);
  }

  @override
  Future<SavedSession?> open(String id) async {
    for (final session in _readAll()) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final sessions = _readAll()..removeWhere((s) => s.id == id);
    await _writeAll(sessions);
  }

  @override
  Future<String?> loadSnapshot() async => _prefs.getString(_snapshotKey);

  @override
  Future<void> saveSnapshot(String snapshotJson) =>
      _prefs.setString(_snapshotKey, snapshotJson);

  @override
  Future<void> clearSnapshot() => _prefs.remove(_snapshotKey);
}
