/// The student's gateway to the proxy.
///
/// Narrower than the teacher's on purpose, and the narrowness is still the
/// security story: there is deliberately no method that takes a class key, so
/// the group cannot grow one.
///
/// What ADR-0020 changed: the student USED to hold the submission id and
/// nothing else, because there was no account to hold anything against. Now
/// the session identifies the group, so [listSubmissions] can ask the server
/// which work is theirs. The id-in-the-path methods stay — a deep link to one
/// submission is still a legitimate way in — but they are no longer the ONLY
/// way, and the carried capability is no longer the whole of the authority.
///
/// The same "a write never trusts its own answer" rule as the teacher side:
/// the comment routes answer the single comment they wrote, not the thread, so
/// callers re-read ([readSubmission]) and render that.
library;

import '../../../requirement_review/services/api_service.dart';
import '../models/student_models.dart';

class StudentRepository {
  StudentRepository(this._api);

  final ApiService _api;

  /// The submissions this account may see (ADR-0020 §4).
  ///
  /// No parameter for WHOSE list: the server reads the scope from the session,
  /// so there is nothing here to tamper with and no way for a student to ask
  /// for another group's work. An account with no membership gets an empty
  /// list, which the screen renders as "chưa được gắn nhóm" rather than as an
  /// error — that state is normal during onboarding.
  Future<List<StudentSubmissionRow>> listSubmissions() async {
    final data = await _api.get('/submissions');
    final rows = data['submissions'] as List<dynamic>? ?? const [];
    return [
      for (final row in rows)
        StudentSubmissionRow.fromJson(
          Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
        ),
    ];
  }

  /// The reading view: metadata, the decision, and the round's thread.
  ///
  /// No credential of any kind rides along — possession of the id in the path
  /// IS the credential (the same posture as `GET /share/{id}`).
  Future<StudentSubmission> readSubmission(String submissionId) async =>
      StudentSubmission.fromJson(await _api.get('/submissions/$submissionId'));

  /// Writes one remark into the round's thread as the student.
  ///
  /// No `writeKey` parameter exists, and that is the point: the student path
  /// is authorised by the submission capability alone, so a caller cannot
  /// accidentally pass a class key here. The server refuses a request that
  /// claims `teacher` without one, which is what stops a group writing as its
  /// own examiner.
  Future<void> addComment({
    required String submissionId,
    required String body,
  }) async {
    await _api.write(
      '/submissions/$submissionId/comments',
      body: {'author': 'student', 'body': body},
    );
  }

  /// Replies under one teacher comment.
  Future<void> replyToComment({
    required String submissionId,
    required String commentId,
    required String body,
  }) async {
    await _api.write(
      '/submissions/$submissionId/comments/$commentId/replies',
      body: {'author': 'student', 'body': body},
    );
  }

  /// Opens the next revision instead of overwriting this one (ADR-0016).
  ///
  /// Answers the NEW row; the caller renders the new id, because showing the
  /// old one after a successful resubmit is how a group resubmits twice.
  Future<StudentSubmission> resubmit({
    required String submissionId,
    String project = '',
    String uploadUri = '',
  }) async {
    final data = await _api.write(
      '/submissions/$submissionId/revise',
      body: {'project': project, 'upload_uri': uploadUri},
    );
    return StudentSubmission.fromJson(data);
  }

  /// The sandboxed HTML twin, joined against the proxy base.
  Future<Uri> reportUri(String submissionId, String baseUrl) async =>
      Uri.parse(baseUrl).resolve('/submissions/$submissionId/report');
}
