/// State and commands for the three teacher screens.
///
/// Mirrors `features/workspace/view_model/workspace_view_model.dart`: a plain
/// Riverpod notifier holding everything the views render, no widgets, no
/// transport imports. The repository and store arrive through
/// `core/providers.dart` (the composition root), so a test overrides two
/// providers and the screens are otherwise untouched.
///
/// The two rules this class exists to hold:
/// * **A write never trusts its own answer.** `file`, `unfile` and `decide`
///   answer thin rows on the wire; the state change is proven by the CLASS
///   READ that follows every write, which is what renders.
/// * **The watermark is this device's, and it advances only when its inbox
///   has actually been rendered** — `markInboxSeen()` runs from the view
///   after a frame that drew the items, not from the fetch.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../requirement_review/services/api_service.dart';
import '../data/teacher_repository.dart';
import '../data/teacher_store.dart';
import '../models/teacher_models.dart';
import 'teacher_reasons.dart';

class TeacherState {
  const TeacherState({
    this.classes = const [],
    this.loading = false,
    this.everOpened = false,
    this.current,
    this.activity,
    this.inbox = const [],
    this.unreadCount = 0,
    this.detail,
    this.reportUrl,
    this.watermark,
    this.busy = false,
    this.notice,
    this.error,
    this.actionFeedback,
    this.lastDeleteOutcome,
  });

  final List<TeacherClassRecord> classes;
  final bool loading;

  /// False until the inbox of SOME class has been rendered once. It is what
  /// makes the first open silent ("everything is simply here") and every
  /// later open able to say "2 new".
  final bool everOpened;
  final TeacherClass? current;
  final TeacherActivity? activity;
  final List<TeacherInboxItem> inbox;

  /// Count of inbox rows marked new — shown on the pull inbox, never
  /// announced on the first open (which has [everOpened] == false).
  final int unreadCount;
  final TeacherSubmissionDetail? detail;

  /// Absolute URL of the sandboxed report page, when the submission has one.
  final Uri? reportUrl;
  final TeacherWatermark? watermark;

  /// True while a write (file/unfile/decide/delete) is in flight.
  final bool busy;

  /// A line the shell may surface as a toast (filing succeeded, etc.).
  final String? notice;

  /// The error the screens render where the user can read it — one line, no
  /// modal. Carries the mapped 409 messages of [teacherDecisionFailureMessage].
  final String? error;

  /// The decision's own feedback line, rendered next to the action buttons
  /// (busy / success / the one-line failure with its mapped reason).
  final String? actionFeedback;
  final TeacherDeleteOutcome? lastDeleteOutcome;

  TeacherState copyWith({
    List<TeacherClassRecord>? classes,
    bool? loading,
    bool? everOpened,
    TeacherClass? current,
    TeacherActivity? activity,
    List<TeacherInboxItem>? inbox,
    int? unreadCount,
    TeacherSubmissionDetail? detail,
    Uri? reportUrl,
    bool clearDetail = false,
    bool clearReportUrl = false,
    bool clearCurrent = false,
    bool clearActivity = false,
    bool clearInbox = false,
    TeacherWatermark? watermark,
    bool? busy,
    String? notice,
    String? error,
    bool clearNotice = false,
    bool clearError = false,
    String? actionFeedback,
    bool clearActionFeedback = false,
    TeacherDeleteOutcome? lastDeleteOutcome,
    bool clearLastDeleteOutcome = false,
  }) => TeacherState(
    classes: classes ?? this.classes,
    loading: loading ?? this.loading,
    everOpened: everOpened ?? this.everOpened,
    current: clearCurrent ? null : (current ?? this.current),
    activity: clearActivity ? null : (activity ?? this.activity),
    inbox: clearInbox ? const [] : (inbox ?? this.inbox),
    unreadCount: clearInbox ? 0 : (unreadCount ?? this.unreadCount),
    detail: clearDetail ? null : (detail ?? this.detail),
    reportUrl: clearReportUrl ? null : (reportUrl ?? this.reportUrl),
    watermark: watermark ?? this.watermark,
    busy: busy ?? this.busy,
    notice: clearNotice ? null : (notice ?? this.notice),
    error: clearError ? null : (error ?? this.error),
    actionFeedback: clearActionFeedback
        ? null
        : (actionFeedback ?? this.actionFeedback),
    lastDeleteOutcome: clearLastDeleteOutcome
        ? null
        : (lastDeleteOutcome ?? this.lastDeleteOutcome),
  );
}

class TeacherViewModel extends Notifier<TeacherState> {
  TeacherRepository get _repository => ref.read(teacherRepositoryProvider);
  TeacherStore get _store => ref.read(teacherStoreProvider);

  @override
  TeacherState build() => const TeacherState();

  // ---------------------------------------------------------------- classes

  /// Loads the saved roster from this device. Does NOT auto-open the last
  /// class: the landing screen is the class list, a tap opens one.
  Future<void> loadSavedClasses() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final classes = await _store.loadClasses();
      final watermark = await _store.loadWatermark();
      state = state.copyWith(
        classes: classes,
        watermark: watermark,
        loading: false,
        everOpened: watermark != null,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        error: 'Không đọc được lớp đã lưu trên máy này: $error',
      );
    }
  }

  /// Mints a class and keeps the write key the server shows exactly once.
  Future<String?> createClass(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Tên lớp không được để trống.';
    state = state.copyWith(busy: true, clearError: true);
    try {
      final record = await _repository.createClass(trimmed);
      await _store.saveClass(record);
      final classes = await _store.loadClasses();
      state = state.copyWith(
        classes: classes,
        busy: false,
        notice: 'Đã tạo lớp "${record.name}". Khoá ghi đã lưu trên máy này.',
      );
      return null;
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        error: _message(error, 'Không tạo được lớp'),
      );
      return state.error;
    }
  }

  Future<String?> renameClass(String classId, String newName) async {
    final record = state.classes.where((c) => c.id == classId).firstOrNull;
    if (record == null) return 'Không tìm thấy lớp trên máy này.';
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return 'Tên lớp không được để trống.';
    state = state.copyWith(busy: true, clearError: true);
    try {
      final renamed = await _repository.renameClass(
        classId,
        record.writeKey,
        name: trimmed,
      );
      await _store.saveClass(renamed);
      final classes = await _store.loadClasses();
      state = state.copyWith(
        classes: classes,
        current: state.current?.copyWith(name: trimmed),
        busy: false,
        notice: 'Đã đổi tên lớp thành "${renamed.name}".',
      );
      return null;
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        error: _message(error, 'Không đổi được tên lớp'),
      );
      return state.error;
    }
  }

  /// Deletes through the class key. The outcome (`unfiled`, `dangling`) is
  /// kept so the class list can render the one-line warning — light, never a
  /// modal, and silent when everything was clean.
  Future<String?> deleteClass(String classId) async {
    final record = state.classes.where((c) => c.id == classId).firstOrNull;
    if (record == null) return 'Không tìm thấy lớp trên máy này.';
    state = state.copyWith(busy: true, clearError: true);
    try {
      final outcome = await _repository.deleteClass(classId, record.writeKey);
      await _store.deleteClass(classId);
      final classes = await _store.loadClasses();
      state = state.copyWith(
        classes: classes,
        busy: false,
        lastDeleteOutcome: outcome,
        notice: 'Đã xoá lớp "${record.name}".',
      );
      if (state.current?.id == classId) {
        state = state.copyWith(
          clearCurrent: true,
          clearActivity: true,
          clearInbox: true,
          clearDetail: true,
          clearReportUrl: true,
        );
      }
      return null;
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        error: _message(error, 'Không xoá được lớp'),
      );
      return state.error;
    }
  }

  // ------------------------------------------------------ class + activity

  /// Opens one class: the member list AND the activity feed in one go. This
  /// IS the inbox pull — it runs when the app opens into a class and every
  /// time the teacher returns to the class screen.
  Future<void> openClass(String classId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repository.readClass(classId),
        _repository.readActivity(classId),
      ]);
      final klass = results[0] as TeacherClass;
      final activity = results[1] as TeacherActivity;
      final inbox = buildInbox(
        klass: klass,
        activity: activity,
        watermark: state.watermark,
        everOpened: state.everOpened,
      );
      state = state.copyWith(
        loading: false,
        current: klass,
        activity: activity,
        inbox: inbox,
        unreadCount: inbox.where((item) => item.isNew).length,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        error: _message(error, 'Không mở được lớp'),
      );
    }
  }

  /// Re-reads the class (and the feed) after a write. The read is the truth.
  Future<void> _refreshCurrent() async {
    final id = state.current?.id;
    if (id == null) return;
    final everOpened = state.everOpened;
    final watermark = state.watermark;
    try {
      final results = await Future.wait([
        _repository.readClass(id),
        _repository.readActivity(id),
      ]);
      final klass = results[0] as TeacherClass;
      final activity = results[1] as TeacherActivity;
      final inbox = buildInbox(
        klass: klass,
        activity: activity,
        watermark: watermark,
        everOpened: everOpened,
      );
      state = state.copyWith(
        current: klass,
        activity: activity,
        inbox: inbox,
        unreadCount: inbox.where((item) => item.isNew).length,
      );
    } on Object {
      // The write itself already succeeded; a failed re-read must not turn
      // a recorded decision into an error story. The next open re-reads.
    }
  }

  /// Called by the view after a frame that actually rendered the inbox: the
  /// watermark moves to the NEWEST event on screen, only if the feed has
  /// events to cover. The first visit records a watermark without ever having
  /// shown a "new" badge — which is exactly the honest order (WP4: the first
  /// open is silent).
  Future<void> markInboxSeen() async {
    final events = state.activity?.events ?? const <TeacherActivityEvent>[];
    if (events.isEmpty) return;
    final newestEvent = events.first;
    final newest = TeacherWatermark(
      submissionId: newestEvent.submissionId,
      revision: newestEvent.revision,
      at: newestEvent.at,
    );
    if (newest == state.watermark && state.unreadCount == 0) return;
    await _store.saveWatermark(newest);
    state = state.copyWith(
      watermark: newest,
      everOpened: true,
      unreadCount: 0,
      inbox: [
        for (final item in state.inbox)
          if (item.isNew)
            TeacherInboxItem(
              submission: item.submission,
              isNew: false,
              event: item.event,
            )
          else
            item,
      ],
    );
  }

  // ------------------------------------------------------------- decisions

  /// Files a submission into the current class, then re-reads. The 404 the
  /// filing route answers (unknown submission, unknown class, wrong key — one
  /// shape by design) is reported through [error] as-is.
  Future<void> fileSubmission(String submissionId) async {
    final current = state.current;
    final record = state.classes.where((c) => c.id == current?.id).firstOrNull;
    if (current == null || record == null) {
      state = state.copyWith(error: 'Chưa mở lớp nào trên máy này.');
      return;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repository.fileSubmission(
        current.id,
        record.writeKey,
        submissionId,
      );
      state = state.copyWith(busy: false, notice: 'Đã gán bài vào lớp.');
      await _refreshCurrent();
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        error: _message(error, 'Không gán được bài vào lớp'),
      );
    }
  }

  /// Removes a submission from the roster; the submission itself survives.
  Future<void> unfileSubmission(String submissionId) async {
    final current = state.current;
    final record = state.classes.where((c) => c.id == current?.id).firstOrNull;
    if (current == null || record == null) {
      state = state.copyWith(error: 'Chưa mở lớp nào trên máy này.');
      return;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repository.unfileSubmission(
        current.id,
        record.writeKey,
        submissionId,
      );
      state = state.copyWith(busy: false, notice: 'Đã bỏ bài khỏi lớp.');
      await _refreshCurrent();
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        error: _message(error, 'Không bỏ được bài khỏi lớp'),
      );
    }
  }

  /// Records the decision for the round, then re-reads the class (the read
  /// is the truth, the write's own thin answer is ignored). Feedback is the
  /// three-line contract: busy while in flight, success when recorded, the
  /// MAPPED one-line message when refused — `not_in_class` and
  /// `class_missing` are different sentences with different fixes.
  Future<void> decide({
    required String submissionId,
    required TeacherDecision decision,
    String note = '',
  }) async {
    // The write key resolves from the SAVED roster, keyed by the submission's
    // own class_id — NOT from the currently open class. A teacher can land on
    // this submission through a deep link (history, a pasted link) with no
    // class screen behind it; requiring `state.current` there would block
    // every decision made from that path.
    final savedClasses = await _store.loadClasses();
    final classId = state.detail?.classId ?? state.current?.id ?? '';
    TeacherClassRecord? record;
    if (classId.isNotEmpty) {
      record = savedClasses.where((c) => c.id == classId).firstOrNull;
      record ??= state.classes.where((c) => c.id == classId).firstOrNull;
    }
    if (record == null) {
      state = state.copyWith(
        actionFeedback:
            'Không có khoá ghi của lớp trên máy này — hãy mở lớp từ danh sách lớp rồi thử lại.',
        error: 'Không có khoá ghi của lớp trên máy này.',
      );
      return;
    }
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearActionFeedback: true,
    );
    try {
      await _repository.decide(
        submissionId: submissionId,
        writeKey: record.writeKey,
        decision: decision,
        note: note,
      );
      state = state.copyWith(
        busy: false,
        actionFeedback: decision == TeacherDecision.approved
            ? 'Đã ghi quyết định: Duyệt bài.'
            : 'Đã ghi quyết định: Yêu cầu sửa.',
      );
      await _refreshCurrent();
    } on Object catch (error) {
      final message = teacherDecisionFailureMessage(error);
      state = state.copyWith(
        busy: false,
        actionFeedback: message,
        error: message,
      );
    }
  }

  // ------------------------------------------------------------ submission

  /// Opens one submission: metadata + numbers, and the report link when the
  /// group attached its twin.
  ///
  /// The link is computed in its OWN guarded step, not in the main try: the
  /// base-url provider is a dependency that can be missing in a bare test
  /// container, and a helper's failure must degrade to "no link shown" — not
  /// swallow the whole submission read into an error state.
  Future<void> openSubmission(String submissionId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final detail = await _repository.readSubmission(submissionId);
      Uri? reportUrl;
      if (detail.hasReport) {
        try {
          reportUrl = await _repository.reportUri(
            submissionId,
            ref.read(teacherApiBaseUrlProvider),
          );
        } on Object {
          reportUrl = null;
        }
      }
      state = state.copyWith(
        loading: false,
        detail: detail,
        reportUrl: reportUrl,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        error: _message(error, 'Không mở được bài nộp'),
      );
    }
  }

  /// Clears the decision feedback line (the view calls it when the teacher
  /// starts another action).
  void clearActionFeedback() {
    state = state.copyWith(clearActionFeedback: true);
  }

  // --------------------------------------------------------------- thread

  /// Writes a remark in the thread — this is how a teacher explains WHY a
  /// round came back, per element, rather than only in the one decision note
  /// that replaces its predecessor each round.
  ///
  /// Carries the class write key WHEN THERE IS ONE. A teacher's authority is
  /// the session first and the key second (ADR-0021); with no key and no
  /// session the store still answers 409 and nothing is written, which is the
  /// rule the store enforces and this method must not paper over.
  Future<void> addComment(String submissionId, String body) async {
    final key = _currentWriteKey();
    if (body.trim().isEmpty) {
      state = state.copyWith(actionFeedback: 'Bình luận không được để trống.');
      return;
    }
    state = state.copyWith(busy: true, clearActionFeedback: true);
    try {
      await _repository.addComment(
        submissionId: submissionId,
        writeKey: key,
        body: body,
      );
      await _reloadDetail(submissionId, feedback: 'Đã thêm bình luận.');
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        actionFeedback: _message(error, 'Không thêm được bình luận'),
      );
    }
  }

  Future<void> replyToComment(
    String submissionId,
    String commentId,
    String body,
  ) async {
    final key = _currentWriteKey();
    if (body.trim().isEmpty) {
      state = state.copyWith(actionFeedback: 'Trả lời không được để trống.');
      return;
    }
    state = state.copyWith(busy: true, clearActionFeedback: true);
    try {
      await _repository.replyToComment(
        submissionId: submissionId,
        commentId: commentId,
        writeKey: key,
        body: body,
      );
      await _reloadDetail(submissionId, feedback: 'Đã gửi trả lời.');
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        actionFeedback: _message(error, 'Không gửi được trả lời'),
      );
    }
  }

  /// Marks a remark handled. Teacher-only, and the gate is on the SERVER, not
  /// here: a student session gets a 403 (ADR-0021) and a keyless caller with no
  /// session gets a 409. The point of "resolved" is that the TEACHER decided
  /// it, so this must not be openable by the group whose work it is.
  Future<void> setCommentResolved(
    String submissionId,
    String commentId,
    bool resolved,
  ) async {
    final key = _currentWriteKey();
    state = state.copyWith(busy: true, clearActionFeedback: true);
    try {
      await _repository.setCommentResolved(
        submissionId: submissionId,
        commentId: commentId,
        writeKey: key,
        resolved: resolved,
      );
      await _reloadDetail(
        submissionId,
        feedback: resolved ? 'Đã đánh dấu xử lý.' : 'Đã mở lại bình luận.',
      );
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        actionFeedback: _message(error, 'Không cập nhật được bình luận'),
      );
    }
  }

  /// The class write key for the submission currently open.
  ///
  /// Read from the SAVED record, not from the submission: a submission knows
  /// its `class_id` but never the key, and the key only exists on the device
  /// that created the class (ADR-0016 — the class capability is non-revocable
  /// and lives with whoever made it).
  ///
  /// `null` here is NOT "you may not write" any more. Since ADR-0021 a signed-in
  /// teacher's SESSION is an authority of its own, so every caller below treats
  /// a null key as "send no key and let the session speak". Blocking on it —
  /// which is what these three methods used to do — meant a teacher who had
  /// signed in on a fresh device, with no saved class on it, was told to "open
  /// the class first" for a class the server already knew they owned.
  String? _currentWriteKey() {
    final classId = state.detail?.classId;
    if (classId == null || classId.isEmpty) return null;
    return state.classes.where((c) => c.id == classId).firstOrNull?.writeKey;
  }

  /// Re-reads the open submission so the thread renders what the SERVER has,
  /// not what the write answered — the same rule as everywhere else: a write's
  /// reply is not evidence the read agrees.
  Future<void> _reloadDetail(
    String submissionId, {
    required String feedback,
  }) async {
    try {
      final detail = await _repository.readSubmission(submissionId);
      state = state.copyWith(
        busy: false,
        detail: detail,
        actionFeedback: feedback,
      );
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        actionFeedback: _message(error, 'Không đọc lại được bài nộp'),
      );
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  static String _message(Object error, String fallback) {
    if (error is ApiException) return error.message;
    return '$fallback: $error';
  }
}
