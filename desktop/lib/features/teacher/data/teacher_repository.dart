/// The teacher's gateway to the proxy — one seam between the screens and the
/// transport, mirroring `requirement_review/repositories/review_repository.dart`.
///
/// Two contracts live in here, both paid for on the server side:
///
/// * **Writes return `void`.** `file`, `unfile` and `decide` answer a THIN row
///   (`{id, class_id, updatedAt}` / `{id, status, decidedAt, ...}`), not the
///   submission — parsing that thin row into a model produced a screen with an
///   empty group name and no error anywhere (the WP5 brief, fact 1). So the
///   repository throws those answers away and the view-model re-READS the
///   class after every write; the read is the truth.
/// * **Every class-scoped write carries `X-Class-Key`** — the credential
///   ADR-0017 gives to renames, deletes, filing and decisions. The app token
///   is a shared secret and does not authorize any of them.
library;

import '../../../requirement_review/services/api_service.dart';
import '../models/teacher_models.dart';

class TeacherRepository {
  TeacherRepository(this._api);

  final ApiService _api;

  // ------------------------------------------------------------- class CRUD

  /// Mints a class. The returned record carries the `write_key` the server
  /// shows exactly once — losing it means losing the class's write power.
  Future<TeacherClassRecord> createClass(String name) async {
    final data = await _api.write('/classes', body: {'name': name});
    return TeacherClassRecord.fromJson({
      'id': data['id'],
      'name': data['name'],
      'writeKey': data['write_key'],
      'savedAt': data['createdAt'],
    });
  }

  Future<TeacherClass> readClass(String classId) async =>
      TeacherClass.fromJson(await _api.get('/classes/$classId'));

  /// Renames through PATCH — the only verb that carries the class key on a
  /// body write, and the reason `_write` grew a PATCH branch.
  Future<TeacherClassRecord> renameClass(
    String classId,
    String writeKey, {
    required String name,
  }) async {
    final data = await _api.write(
      '/classes/$classId',
      method: 'PATCH',
      body: {'name': name},
      writeKey: writeKey,
    );
    return TeacherClassRecord.fromJson({
      'id': data['id'],
      'name': data['name'],
      'writeKey': writeKey,
      'savedAt': data['createdAt'],
    });
  }

  Future<TeacherDeleteOutcome> deleteClass(String classId, String writeKey) =>
      _api
          .write('/classes/$classId', method: 'DELETE', writeKey: writeKey)
          .then((data) => TeacherDeleteOutcome.fromJson(classId, data));

  // ---------------------------------------------------------------- roster

  Future<TeacherActivity> readActivity(String classId) async =>
      TeacherActivity.fromJson(await _api.get('/classes/$classId/activity'));

  /// Files an existing submission into this class. Returns nothing on
  /// purpose — the thin row it answers has no group/project/revision, and a
  /// caller that rendered it would show a blank row with no error. Callers
  /// re-read the class instead ([readClass]).
  Future<void> fileSubmission(
    String classId,
    String writeKey,
    String submissionId,
  ) async {
    await _api.write(
      '/classes/$classId/submissions',
      body: {'submission_id': submissionId},
      writeKey: writeKey,
    );
  }

  /// Removes one submission from the roster; the submission itself survives.
  Future<void> unfileSubmission(
    String classId,
    String writeKey,
    String submissionId,
  ) async {
    await _api.write(
      '/classes/$classId/submissions/$submissionId',
      method: 'DELETE',
      writeKey: writeKey,
    );
  }

  // -------------------------------------------------------------- decisions

  /// The full row behind one submission — the reading view of screen 3.
  Future<TeacherSubmissionDetail> readSubmission(String submissionId) async =>
      TeacherSubmissionDetail.fromJson(
        await _api.get('/submissions/$submissionId'),
      );

  /// The teacher's decision on one round. Vocabulary is closed by the server
  /// (`approved` | `changes_requested`); anything else is a 422 before the
  /// store ever sees it. Returns nothing — re-read ([readClass]) for truth.
  ///
  /// The class key rides in `X-Class-Key`: the containing class's key is the
  /// authority, NOT the app token, which the group's own app also holds.
  /// Accepting the token here would let a group approve its own work.
  Future<void> decide({
    required String submissionId,
    required String writeKey,
    required TeacherDecision decision,
    String note = '',
  }) async {
    await _api.write(
      '/submissions/$submissionId/decision',
      body: {'decision': decision.wire, 'note': note},
      writeKey: writeKey,
    );
  }

  /// The sandboxed HTML twin, joined against the configured proxy base so
  /// the webview can load it as a page.
  Future<Uri> reportUri(String submissionId, String baseUrl) async =>
      Uri.parse(baseUrl).resolve('/submissions/$submissionId/report');
}

/// The two outcomes the plan fixed for one round. The wire words are the
/// server's closed vocabulary — never extended here.
enum TeacherDecision {
  approved('approved'),
  changesRequested('changes_requested');

  const TeacherDecision(this.wire);

  final String wire;
}
