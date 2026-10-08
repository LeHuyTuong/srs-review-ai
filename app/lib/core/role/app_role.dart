/// Who this build is acting as — deliberately NOT part of [AppPlatform].
///
/// ADR-0015, decision 1. The separation is load-bearing, and the reason is
/// lifetime, not taste:
///
/// * [AppPlatform] answers *where am I running?* — a runtime property. Drag the
///   window and `formFactor` changes.
/// * [AppRole] answers *who is this for?* — a property of the build and of the
///   session. It does not change when a window is resized.
///
/// Folding role into `AppPlatform` would make every layout call site re-derive
/// identity, and would make a role switch drag the device answer along with it.
///
/// What this module is NOT
/// =======================
/// It is not an auth system. There is no token, no account, no server check —
/// a role here is a *build-time* statement of intent, exactly as honest as the
/// capability-URL submission model on the server (plan 9 §5): whoever holds the
/// link can read it, and nothing here pretends otherwise.
///
/// It has no consumer yet, on purpose. A concept nobody reads is a promise, not
/// a feature, and ADR-0015 records it as accepted debt rather than as P3
/// progress. What the role is FOR is the shell: it selects which shell to mount,
/// and the shell — not this file, not any layout code — is what branches.
library;

/// The two clients of the same review engine.
enum AppRole {
  /// A group working on its own artifacts: import, review, revise.
  student,

  /// A teacher reviewing submissions: read, triage, comment, approve.
  teacher;

  /// Coarse bucket, used only to pick a shell and a copy variant.
  ///
  /// Deliberately NOT a form factor: [AppRole.student] runs on desktop AND
  /// mobile, and so does [AppRole.teacher]. Keeping the two axes separate is
  /// what makes "teacher on a phone" expressible without a new enum member.
  String get title => switch (this) {
    AppRole.student => 'Nhóm sinh viên',
    AppRole.teacher => 'Giáo viên',
  };

  /// True when this role only ever READS submissions.
  ///
  /// A teacher client never uploads an artifact and never runs a review of its
  /// own; it consumes what a group produced. Stating that here keeps the shell
  /// from re-deriving it, and gives P2's capability model something honest to
  /// assert against.
  bool get isReadOnly => this == AppRole.teacher;
}

/// Wire values for [AppRole], for the account routes (ADR-0020).
///
/// The mapping lives HERE, next to the enum, and not in the auth feature:
/// `teacher`/`student` are the server's own strings (`accounts.ROLES`), and a
/// second copy of them elsewhere is how a typo becomes "server says 422" with
/// no hint about which spelling it wanted.
extension AppRoleWire on AppRole {
  /// The string the server uses for this role.
  String get wire => switch (this) {
    AppRole.student => 'student',
    AppRole.teacher => 'teacher',
  };
}

/// Reads a wire role string.
///
/// A top-level function, not a static on the extension: Dart extensions cannot
/// declare statics, and the compiler's message for trying is not one that
/// points at the cause.
///
/// The default is deliberate and is the SAFER one: an unrecognised role string
/// means this app does not understand the account it just signed into, and
/// treating it as the student client shows FEWER controls than treating it as a
/// teacher would. Failing open here would hand an unknown account the teacher
/// shell.
AppRole appRoleFromWire(String wire) => switch (wire) {
  'teacher' => AppRole.teacher,
  _ => AppRole.student,
};

/// The role this build runs as.
///
/// Defaults to [AppRole.student] — the historical, fully-working client. A
/// teacher build passes a different value at startup; nothing in the app writes
/// to it at runtime, because nothing should be able to escalate a running build
/// into a teacher client.
class AppRoleScope {
  const AppRoleScope({required this.role});

  const AppRoleScope.student() : role = AppRole.student;

  const AppRoleScope.teacher() : role = AppRole.teacher;

  final AppRole role;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppRoleScope && other.role == role;

  @override
  int get hashCode => role.hashCode;

  @override
  String toString() => 'AppRoleScope($role)';
}
