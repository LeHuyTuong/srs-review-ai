/// The signed-in session, as a Riverpod notifier (ADR-0020).
///
/// Four states, and the difference between them is the whole point of this
/// class:
///
/// * **asking** — the app has not heard from `/auth/me` yet. The shell shows a
///   spinner. Rendering a login form here would flash it on every cold start of
///   an already-signed-in user.
/// * **signed out** — the server said no. The shell shows the form.
/// * **signed in** — an identity came back, and the cookie is installed on the
///   transport.
/// * **offline** — the network failed while asking. Deliberately NOT folded into
///   "signed out": a blip must not throw a signed-in user back to a login form
///   they cannot use either, because the login call will fail too.
///
/// The role is read from the SERVER's answer, never from the build. `AppRoleScope`
/// used to be a compile-time statement; with real accounts it is a fact that
/// arrives over the wire, and a shell that trusted the build would show the
/// teacher UI to whoever opened the teacher binary.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/role/app_role.dart';
import '../../../requirement_review/services/api_service.dart';
import '../data/auth_service.dart';

enum SessionStatus { asking, signedOut, signedIn, offline }

class SessionState {
  const SessionState({
    this.status = SessionStatus.asking,
    this.identity,
    this.busy = false,
    this.error,
  });

  final SessionStatus status;
  final AccountIdentity? identity;
  final bool busy;
  final String? error;

  AppRole? get role => identity?.role;
  bool get isSignedIn => status == SessionStatus.signedIn && identity != null;
}

class SessionViewModel extends Notifier<SessionState> {
  AuthService get _auth => ref.read(authServiceProvider);

  @override
  SessionState build() {
    // Same microtask pattern as the other view-models: the first frame paints
    // the spinner, and the answer arrives without blocking it.
    Future.microtask(restore);
    return const SessionState();
  }

  /// Asks the server who this device is. Called once at start-up.
  Future<void> restore() async {
    state = const SessionState();
    try {
      final identity = await _auth.whoami();
      _installCookie();
      if (identity == null) {
        state = const SessionState(status: SessionStatus.signedOut);
        return;
      }
      state = SessionState(
        status: SessionStatus.signedIn,
        identity: identity,
        // Reported alongside a SUCCESSFUL sign-in, because that is what
        // happened: the identity is real, the transport is not wired. Hiding
        // it makes every later 401 look like a permissions bug.
        error: _installFailure == null
            ? null
            : 'Không gắn được phiên vào yêu cầu: $_installFailure',
      );
    } catch (error) {
      // A dead proxy, not a rejected credential. Keeping the previous status
      // would be a lie in the other direction; `offline` says what happened.
      state = SessionState(
        status: SessionStatus.offline,
        error: 'Không kết nối được máy chủ: $error',
      );
    }
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    state = const SessionState(status: SessionStatus.asking, busy: true);
    try {
      final identity = await _auth.signIn(
        username: username,
        password: password,
      );
      _installCookie();
      state = SessionState(status: SessionStatus.signedIn, identity: identity);
    } on SignInRejected catch (error) {
      state = SessionState(
        status: SessionStatus.signedOut,
        error: error.message,
      );
    } catch (error) {
      state = SessionState(
        status: SessionStatus.signedOut,
        error: 'Không kết nối được máy chủ: $error',
      );
    }
  }

  Future<void> register({
    required String username,
    required String password,
    required AppRole role,
    String? classId,
    String? group,
  }) async {
    state = const SessionState(status: SessionStatus.asking, busy: true);
    try {
      final identity = await _auth.register(
        username: username,
        password: password,
        role: role,
        classId: classId,
        group: group,
      );
      _installCookie();
      state = SessionState(status: SessionStatus.signedIn, identity: identity);
    } on SignInRejected catch (error) {
      state = SessionState(
        status: SessionStatus.signedOut,
        error: error.message,
      );
    } catch (error) {
      // A 409 (name taken) or 422 (input refused) arrives here as an
      // ApiException; its message is already written for a person.
      state = SessionState(
        status: SessionStatus.signedOut,
        error: _readable(error),
      );
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // The cookie is cleared on the transport too, so a request fired between
    // this and the next `restore` cannot carry a token the server just revoked.
    ref.read(teacherApiProvider).setSessionCookie(null);
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// Puts the token on the transport. Until this runs, every authenticated
  /// route would answer 401 while the app believes it is signed in — which is
  /// why it is called on BOTH success paths and on restore.
  void _installCookie() {
    final cookie = _auth.cookie;
    // Guarded, and on purpose. Reading `teacherApiProvider` builds an
    // ApiService, which reads `sharedPreferencesProvider` — and if that is not
    // overridden (a plain `flutter test`, or a wiring mistake in main) the read
    // THROWS. Unguarded, that throw lands in `restore`'s catch and is reported
    // as `SessionStatus.offline`, so a configuration bug is displayed to the
    // user as "cannot reach the server" and the real cause is never seen. The
    // identity is already known at this point; failing to attach its cookie is
    // a transport fault that the next authenticated request will surface
    // honestly, rather than a reason to claim the whole session is unknown.
    try {
      ref.read(teacherApiProvider).setSessionCookie(cookie?.headerValue);
    } on Object catch (error) {
      // Not swallowed silently: the state carries both facts, so the screen
      // can still sign the user in while the message names the real problem.
      _installFailure = '$error';
    }
  }

  /// Set when the cookie could not be attached. Surfaced rather than hidden.
  String? _installFailure;

  /// Prefers the server's own sentence over a generic wrapper.
  ///
  /// A 409 from `/auth/register` carries `username 'x' is taken` — actionable.
  /// `ApiException: ...` is not. `ApiException.message` is already written for
  /// the person in front of the screen (that is what it documents), so it is
  /// used verbatim; anything else falls back to its `toString`.
  String _readable(Object error) =>
      error is ApiException ? error.message : '$error';
}
