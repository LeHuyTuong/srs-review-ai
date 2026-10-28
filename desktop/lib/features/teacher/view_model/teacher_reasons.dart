/// Turning a failure into the ONE sentence the teacher acts on.
///
/// The two 409 reasons of the decision route are two different actions, so
/// they are two different messages (WP3 note, ADR-0016/0017):
///
/// * `not_in_class` — the submission belongs to no class: the fix is to file
///   it. Telling the teacher "wrong key" here would send them re-typing a key
///   that was never the problem.
/// * `class_missing` — the class row is gone OR the key does not match. The
///   ambiguity is DELIBERATE (ADR-0017): a wrong key must not confirm the
///   class exists, so the app cannot split this reason into two, and the
///   message keeps the "or" on screen. Splitting it client-side would turn
///   the write path into an existence oracle through the app.
library;

import '../../../requirement_review/services/api_service.dart';
import '../data/teacher_store.dart';
import '../models/teacher_models.dart';

/// The machine reasons this feature maps. Anything else falls to the generic
/// message rather than to a guessed one.
const String reasonNotInClass = 'not_in_class';
const String reasonClassMissing = 'class_missing';

/// The message for a failed decision, from the [ApiException] the repository
/// rethrew. One line, no modal — the screen shows it where the buttons are.
String teacherDecisionFailureMessage(Object error) {
  if (error is! ApiException) return 'Không ghi được quyết định: $error';
  return switch (error.detail) {
    reasonNotInClass =>
      'Bài này chưa được gán vào lớp nào — hãy gán bài vào lớp trước khi duyệt.',
    reasonClassMissing =>
      'Lớp không còn tồn tại, hoặc khoá nhập không đúng — hãy tạo lại lớp hoặc nhập lại khoá.',
    _ => error.message,
  };
}

/// True when [error] means the submission is not filed into this class —
/// the ONE 409 the inbox can fix in place, by offering the filing action.
bool isNotInClassError(Object error) =>
    error is ApiException && error.detail == reasonNotInClass;

/// The machine reason behind a failed decision, for callers that branch on it
/// (the inbox offers the filing action ONLY for `not_in_class`). `null` when
/// the failure carried no named reason — the generic message covers those.
String? decisionReasonOf(Object error) =>
    error is ApiException ? error.detail : null;

/// A row for the submission screen: what the class read says, and what this
/// device's watermark already covered. Pure value, computed in the view-model
/// so the view renders instead of deciding.
class TeacherInboxItem {
  const TeacherInboxItem({
    required this.submission,
    required this.isNew,
    required this.event,
  });

  final TeacherSubmission submission;

  /// True when this device has never rendered this (submission, revision) —
  /// false both for seen rows and for the first open before any render.
  final bool isNew;

  /// The newest activity event naming this submission, when the feed has one.
  final TeacherActivityEvent? event;
}

/// The inbox filter the plan describes: pull when the app opens, mark what is
/// new for THIS device, never announce a backlog on the very first open.
///
/// "New" means: the row has activity STRICTLY NEWER than this device's
/// watermark (a cursor over the feed), AND the device has opened before.
/// On the first open everything is simply here — announcing "12 new" would be
/// the wrong sentence the plan calls out by name.
List<TeacherInboxItem> buildInbox({
  required TeacherClass klass,
  required TeacherActivity? activity,
  required TeacherWatermark? watermark,
  required bool everOpened,
}) {
  final latestBySubmission = <String, TeacherActivityEvent>{};
  for (final event in activity?.events ?? const <TeacherActivityEvent>[]) {
    if (!latestBySubmission.containsKey(event.submissionId)) {
      latestBySubmission[event.submissionId] = event;
    }
  }
  return [
    for (final submission in klass.submissions)
      TeacherInboxItem(
        submission: submission,
        event: latestBySubmission[submission.id],
        isNew: _isNewRow(
          everOpened: everOpened,
          event: latestBySubmission[submission.id],
          watermark: watermark,
        ),
      ),
  ];
}

/// New needs a previous open to be new AGAINST, and an event to be newer
/// than. `everOpened == true` with no watermark yet means the last open
/// predates every event on the feed, so the feed decides.
bool _isNewRow({
  required bool everOpened,
  required TeacherActivityEvent? event,
  required TeacherWatermark? watermark,
}) {
  if (!everOpened || event == null) return false;
  final seenAt = watermark?.at ?? DateTime.fromMillisecondsSinceEpoch(0);
  return event.at.isAfter(seenAt);
}
