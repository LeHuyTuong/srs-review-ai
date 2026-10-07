/// State and commands for the student's "Phản hồi từ giáo viên" screen.
///
/// Mirrors the teacher view-model: a plain Riverpod notifier holding what the
/// view renders, no widgets, no transport imports. The repository and store
/// arrive through `core/providers.dart`, so a test overrides two providers and
/// the screen is otherwise untouched.
///
/// The three rules this class exists to hold:
///
/// * **A write never trusts its own answer.** `addComment`/`replyToComment`
///   answer the single comment they wrote; the state change is proven by the
///   READ that follows, which is what renders.
/// * **The resubmit rule lives in `canResubmit`, not in the button.** The rule
///   is "only after the teacher returned the round" and the server does NOT
///   enforce it — so the gate is this one getter, and the view asks it rather
///   than re-deriving the condition. A button that carried its own copy of the
///   rule is how the two drift.
/// * **The watermark is this device's, and it advances only when the thread
///   has actually been rendered** — [markSeen] runs from the view after a
///   frame that DREW the comments, never from the fetch. Marking on fetch
///   would clear the badge for remarks the student never saw.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/student_repository.dart';
import '../data/student_store.dart';
import '../models/student_models.dart';

class StudentState {
  const StudentState({
    this.links = const [],
    this.loading = false,
    this.submission,
    this.reportUrl,
    this.watermark,
    this.busy = false,
    this.error,
    this.actionFeedback,
  });

  final List<SavedSubmissionLink> links;
  final bool loading;
  final StudentSubmission? submission;
  final Uri? reportUrl;

  /// The high-water mark this device has rendered for the CURRENT submission.
  final StudentWatermark? watermark;
  final bool busy;
  final String? error;

  /// One line the screen shows after a write ("Đã gửi phản hồi"). Kept
  /// separate from [error] so a success and a failure cannot be confused.
  final String? actionFeedback;

  /// Remarks the teacher wrote that this phone has not drawn yet.
  ///
  /// Derived on read, exactly as ADR-0016 decision 4 requires: there is no
  /// server-side read state to consult, so the count is a comparison between
  /// the thread and this device's watermark. An out-of-order or unparsable
  /// timestamp counts as unread — showing one remark twice is a smaller error
  /// than hiding one the student needed.
  int get unreadTeacherComments {
    final current = submission;
    if (current == null) return 0;
    final mark = watermark;
    return current.comments
        .where((c) => c.isTeacher && !c.isResolved)
        .where((c) => mark == null || c.at.isAfter(mark.at))
        .length;
  }

  /// Can the group submit again? See [StudentSubmission.canResubmit] — the
  /// rule is stated once, there, and this is the view's way in.
  bool get canResubmit => submission?.canResubmit ?? false;
}

class StudentViewModel extends Notifier<StudentState> {
  StudentRepository get _repository => ref.read(studentRepositoryProvider);
  StudentStore get _store => ref.read(studentStoreProvider);

  @override
  StudentState build() {
    // Kick off the saved-link load without blocking the first frame, the same
    // microtask pattern the workspace view-model uses for its own restore.
    Future.microtask(loadSavedLinks);
    return const StudentState(loading: true);
  }

  Future<void> loadSavedLinks() async {
    try {
      final links = await _store.loadLinks();
      final watermark = await _store.loadWatermark();
      state = StudentState(links: links, watermark: watermark);
    } catch (error) {
      state = StudentState(error: 'Không đọc được danh sách đã lưu: $error');
    }
  }

  /// Opens one submission by id — the id IS the credential, so nothing else
  /// is asked for. Also remembers the link, so a student who pastes it once
  /// does not paste it again.
  Future<void> openSubmission(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      state = StudentState(links: state.links, error: 'Chưa có mã bài nộp.');
      return;
    }
    state = StudentState(
      links: state.links,
      loading: true,
      watermark: state.watermark,
    );
    try {
      final submission = await _repository.readSubmission(trimmed);
      await _store.saveLink(
        SavedSubmissionLink(
          id: submission.id,
          label: submission.project.isEmpty
              ? submission.group
              : submission.project,
          savedAt: DateTime.now(),
        ),
      );
      final links = await _store.loadLinks();
      state = StudentState(
        links: links,
        submission: submission,
        watermark: state.watermark,
      );
    } catch (error) {
      state = StudentState(
        links: state.links,
        error: 'Không mở được bài nộp: $error',
      );
    }
  }

  /// Forgets a saved link. Local only — nothing on the server is touched,
  /// because the server never knew this list existed.
  Future<void> forgetLink(String id) async {
    await _store.deleteLink(id);
    state = StudentState(
      links: await _store.loadLinks(),
      submission: state.submission,
      watermark: state.watermark,
    );
  }

  Future<void> addComment(String body) async {
    final current = state.submission;
    if (current == null) return;
    if (body.trim().isEmpty) {
      state = _withFeedback('Phản hồi không được để trống.');
      return;
    }
    state = _withBusy(true);
    try {
      await _repository.addComment(submissionId: current.id, body: body);
      await _reload(current.id, feedback: 'Đã gửi phản hồi.');
    } catch (error) {
      state = _withBusy(false, error: 'Không gửi được phản hồi: $error');
    }
  }

  Future<void> replyTo(String commentId, String body) async {
    final current = state.submission;
    if (current == null) return;
    if (body.trim().isEmpty) {
      state = _withFeedback('Trả lời không được để trống.');
      return;
    }
    state = _withBusy(true);
    try {
      await _repository.replyToComment(
        submissionId: current.id,
        commentId: commentId,
        body: body,
      );
      await _reload(current.id, feedback: 'Đã gửi trả lời.');
    } catch (error) {
      state = _withBusy(false, error: 'Không gửi được trả lời: $error');
    }
  }

  /// Opens the next revision. Refuses when [StudentState.canResubmit] is
  /// false, so a caller that skipped the button still cannot bury a round the
  /// teacher is reading — the rule is enforced here too, not only in the view.
  Future<void> resubmit() async {
    final current = state.submission;
    if (current == null) return;
    if (!current.canResubmit) {
      state = _withFeedback(
        'Chưa thể nộp lại: giáo viên chưa yêu cầu chỉnh sửa.',
      );
      return;
    }
    state = _withBusy(true);
    try {
      final created = await _repository.resubmit(
        submissionId: current.id,
        project: current.project,
      );
      // Render the NEW id: showing the old one after a successful resubmit is
      // how a group resubmits twice.
      final links = await _store.loadLinks();
      state = StudentState(
        links: links,
        submission: created,
        watermark: state.watermark,
        actionFeedback: 'Đã mở vòng ${created.revision}.',
      );
    } catch (error) {
      state = _withBusy(false, error: 'Không nộp lại được: $error');
    }
  }

  /// Advances this device's watermark to the newest remark on screen.
  ///
  /// Called by the VIEW after a frame that actually drew the thread — never
  /// from a fetch, which would clear the badge for remarks nobody saw.
  Future<void> markSeen() async {
    final current = state.submission;
    if (current == null || current.comments.isEmpty) return;
    final newest = current.comments
        .map((c) => c.at)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final mark = StudentWatermark(
      submissionId: current.id,
      revision: current.revision,
      at: newest,
    );
    await _store.saveWatermark(mark);
    state = StudentState(
      links: state.links,
      submission: current,
      reportUrl: state.reportUrl,
      watermark: mark,
      busy: state.busy,
      error: state.error,
      actionFeedback: state.actionFeedback,
    );
  }

  Future<void> _reload(String id, {String? feedback}) async {
    try {
      final submission = await _repository.readSubmission(id);
      state = StudentState(
        links: state.links,
        submission: submission,
        watermark: state.watermark,
        actionFeedback: feedback,
      );
    } catch (error) {
      state = _withBusy(false, error: 'Không đọc lại được bài nộp: $error');
    }
  }

  StudentState _withBusy(bool busy, {String? error}) => StudentState(
    links: state.links,
    submission: state.submission,
    reportUrl: state.reportUrl,
    watermark: state.watermark,
    busy: busy,
    error: error,
    actionFeedback: state.actionFeedback,
  );

  StudentState _withFeedback(String feedback) => StudentState(
    links: state.links,
    submission: state.submission,
    reportUrl: state.reportUrl,
    watermark: state.watermark,
    busy: state.busy,
    error: state.error,
    actionFeedback: feedback,
  );
}
