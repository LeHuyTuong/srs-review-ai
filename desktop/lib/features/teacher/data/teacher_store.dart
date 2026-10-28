/// Where this device keeps the classes it mints.
///
/// The write key is the reason this store exists at all: the server shows it
/// exactly once, on create, and every later write on the class (rename,
/// delete, filing, decisions) needs it. So the roster of classes is machine
/// state that must survive a restart, and the seam is the same one the
/// session history uses — `shared_preferences` behind an interface, with an
/// in-memory implementation for tests.
///
/// The watermark lives here too (ADR-0016 decision 4): the server never
/// stores read state, so "seen" is per-device by design. That is also why the
/// inbox copy says so — the watermark says nothing about any other device.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/teacher_models.dart';

/// One seen mark of the pull inbox: the newest activity event this device
/// had rendered when the user last closed the inbox. A CURSOR over the feed,
/// not a per-row flag — the feed is how the server speaks, so "seen" is the
/// newest event rendered, and anything the feed answers OLDER than the cursor
/// was on screen when the cursor was written.
class TeacherWatermark {
  const TeacherWatermark({
    required this.submissionId,
    required this.revision,
    required this.at,
  });

  factory TeacherWatermark.fromJson(Map<String, dynamic> json) =>
      TeacherWatermark(
        submissionId: json['submissionId'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        at:
            DateTime.tryParse(json['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String submissionId;
  final int revision;

  /// When the marked event happened — the comparison key against future
  /// events (same server clock, ISO-8601, so string time is enough).
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'submissionId': submissionId,
    'revision': revision,
    'at': at.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeacherWatermark &&
          other.submissionId == submissionId &&
          other.revision == revision &&
          other.at == at;

  @override
  int get hashCode => Object.hash(submissionId, revision, at);
}

abstract interface class TeacherStore {
  /// Saved classes, newest mint first.
  Future<List<TeacherClassRecord>> loadClasses();

  Future<void> saveClass(TeacherClassRecord record);

  Future<void> deleteClass(String classId);

  /// The newest mark this device has seen — `null` before the first open,
  /// which is a DIFFERENT state from "seen everything up to X" (WP4: the
  /// first open must not announce a backlog it has never rendered).
  Future<TeacherWatermark?> loadWatermark();

  Future<void> saveWatermark(TeacherWatermark watermark);
}

/// Test double — no persistence, no plugin channel.
class MemoryTeacherStore implements TeacherStore {
  final List<TeacherClassRecord> _classes = [];
  TeacherWatermark? _watermark;

  @override
  Future<List<TeacherClassRecord>> loadClasses() async {
    final classes = [..._classes];
    classes.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return classes;
  }

  @override
  Future<void> saveClass(TeacherClassRecord record) async {
    _classes.removeWhere((c) => c.id == record.id);
    _classes.add(record);
  }

  @override
  Future<void> deleteClass(String classId) async =>
      _classes.removeWhere((c) => c.id == classId);

  @override
  Future<TeacherWatermark?> loadWatermark() async => _watermark;

  @override
  Future<void> saveWatermark(TeacherWatermark watermark) async =>
      _watermark = watermark;
}

/// The real store: one JSON list under [SharedPreferencesTeacherStore.classesKey], the
/// watermark under [SharedPreferencesTeacherStore.watermarkKey].
class SharedPreferencesTeacherStore implements TeacherStore {
  SharedPreferencesTeacherStore(this._prefs);

  final SharedPreferences _prefs;

  static const String classesKey = 'srs.teacher.classes';
  static const String watermarkKey = 'srs.teacher.watermark';

  @override
  Future<List<TeacherClassRecord>> loadClasses() async {
    final raw = _prefs.getString(classesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(TeacherClassRecord.fromJson)
          .toList();
      rows.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return rows;
    } on FormatException {
      // A rotting roster must not brick the teacher app: start over rather
      // than crash on every open. Losing saved write keys is recoverable the
      // same way losing a paper slip is — mint the class again.
      return const [];
    }
  }

  @override
  Future<void> saveClass(TeacherClassRecord record) async {
    final classes = [
      ...await loadClasses().then(
        (rows) => rows.where((r) => r.id != record.id),
      ),
      record,
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await _prefs.setString(
      classesKey,
      jsonEncode([for (final c in classes) c.toJson()]),
    );
  }

  @override
  Future<void> deleteClass(String classId) async {
    final classes = await loadClasses();
    await _prefs.setString(
      classesKey,
      jsonEncode([
        for (final c in classes)
          if (c.id != classId) c.toJson(),
      ]),
    );
  }

  @override
  Future<TeacherWatermark?> loadWatermark() async {
    final raw = _prefs.getString(watermarkKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TeacherWatermark.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveWatermark(TeacherWatermark watermark) =>
      _prefs.setString(watermarkKey, jsonEncode(watermark.toJson()));
}

/// The seam the native-plugin guardrail registers: the ONLY place this
/// feature is allowed to construct a store from a `SharedPreferences`
/// instance. `main()` overrides the provider with the awaited instance, and
/// every test injects [MemoryTeacherStore] instead — no test ever touches a
/// plugin channel.
TeacherStore openTeacherStore(SharedPreferences prefs) =>
    SharedPreferencesTeacherStore(prefs);
