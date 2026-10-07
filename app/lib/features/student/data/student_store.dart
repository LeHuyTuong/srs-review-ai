/// What the student app remembers on THIS device.
///
/// Two things, and both are deliberately local (ADR-0016 decision 4):
///
/// * **The saved link.** A student opens the submission id the teacher handed
///   out — pasted, or from a QR. Remembering it is a convenience, not a
///   credential store: the id is not a secret, and losing it costs one paste.
/// * **The read watermark.** "Đã đọc" is a machine-and-phone concern. The
///   server keeps NO `read_state` table and does not know who is reading, so
///   the count of new remarks is derived by comparing this device's watermark
///   against the thread it just fetched. Correctly stated: this is what THIS
///   phone has SEEN, and it says nothing about any other device — the same
///   wording the teacher store uses, for the same reason.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved submission link plus when it was saved, so the list can sort.
class SavedSubmissionLink {
  const SavedSubmissionLink({
    required this.id,
    required this.label,
    required this.savedAt,
  });

  factory SavedSubmissionLink.fromJson(Map<String, dynamic> json) =>
      SavedSubmissionLink(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final String label;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'savedAt': savedAt.toIso8601String(),
  };
}

/// The high-water mark of what this phone has rendered for one submission.
///
/// Keyed by `(submissionId, revision)` — NOT by submission alone — because a
/// resubmit starts a fresh round: remarks written against revision 1 are not
/// "new" for revision 2, and a watermark that ignored the revision would either
/// hide new ones or nag about old ones.
class StudentWatermark {
  const StudentWatermark({
    required this.submissionId,
    required this.revision,
    required this.at,
  });

  factory StudentWatermark.fromJson(Map<String, dynamic> json) =>
      StudentWatermark(
        submissionId: json['submissionId'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        at:
            DateTime.tryParse(json['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String submissionId;
  final int revision;

  /// The newest comment timestamp this phone has actually drawn.
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'submissionId': submissionId,
    'revision': revision,
    'at': at.toIso8601String(),
  };
}

/// The device-local store, behind an interface so tests inject memory.
abstract interface class StudentStore {
  Future<List<SavedSubmissionLink>> loadLinks();
  Future<void> saveLink(SavedSubmissionLink link);
  Future<void> deleteLink(String id);
  Future<StudentWatermark?> loadWatermark();
  Future<void> saveWatermark(StudentWatermark watermark);
}

class MemoryStudentStore implements StudentStore {
  final List<SavedSubmissionLink> _links = [];
  StudentWatermark? _watermark;

  @override
  Future<List<SavedSubmissionLink>> loadLinks() async => List.of(_links);

  @override
  Future<void> saveLink(SavedSubmissionLink link) async {
    _links.removeWhere((l) => l.id == link.id);
    _links.add(link);
  }

  @override
  Future<void> deleteLink(String id) async =>
      _links.removeWhere((l) => l.id == id);

  @override
  Future<StudentWatermark?> loadWatermark() async => _watermark;

  @override
  Future<void> saveWatermark(StudentWatermark watermark) async =>
      _watermark = watermark;
}

/// The production store. Same degradation rule as the teacher side: a rotting
/// saved list must not brick the app, so bad JSON starts over rather than
/// crashing on every open.
class SharedPreferencesStudentStore implements StudentStore {
  SharedPreferencesStudentStore(this._prefs);

  final SharedPreferences _prefs;

  static const String linksKey = 'srs.student.links';
  static const String watermarkKey = 'srs.student.watermark';

  @override
  Future<List<SavedSubmissionLink>> loadLinks() async {
    final raw = _prefs.getString(linksKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SavedSubmissionLink.fromJson)
          .toList();
      rows.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return rows;
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> saveLink(SavedSubmissionLink link) async {
    final links = [...(await loadLinks()).where((l) => l.id != link.id), link]
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await _prefs.setString(
      linksKey,
      jsonEncode([for (final l in links) l.toJson()]),
    );
  }

  @override
  Future<void> deleteLink(String id) async {
    final links = (await loadLinks()).where((l) => l.id != id).toList();
    await _prefs.setString(
      linksKey,
      jsonEncode([for (final l in links) l.toJson()]),
    );
  }

  @override
  Future<StudentWatermark?> loadWatermark() async {
    final raw = _prefs.getString(watermarkKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return StudentWatermark.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveWatermark(StudentWatermark watermark) async =>
      _prefs.setString(watermarkKey, jsonEncode(watermark.toJson()));
}

/// Opens the production store. Mirrors `openTeacherStore`: synchronous, because
/// the `sharedPreferencesProvider` has already awaited the plugin, and the one
/// place that would have failed is already behind that provider.
StudentStore openStudentStore(SharedPreferences prefs) =>
    SharedPreferencesStudentStore(prefs);
