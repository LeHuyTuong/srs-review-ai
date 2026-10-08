/// Who is signed in on THIS device, and the cookie that proves it (ADR-0020).
///
/// The server's session is an **opaque token in an `HttpOnly` cookie**, and a
/// browser would carry it automatically. The Flutter app is not a browser: it
/// gets the raw `Set-Cookie` header back and nothing stores it for it. So the
/// job here is deliberately small and explicit — keep the cookie string, put
/// it on every later request, and forget it on logout.
///
/// Three decisions, each with a reason a reader can check:
///
/// * **The cookie value is treated as a secret.** It is stored behind the
///   same provider chain as everything else local, and it is NEVER logged or
///   put into an error message. A token in a log is a token someone else has.
/// * **`HttpOnly` means nothing HERE, and pretending otherwise would be the
///   bug.** The flag is enforced by browsers; on this side the whole point of
///   parsing `Set-Cookie` is to read a value the flag was meant to hide from
///   scripts. That is only acceptable because the same code owns both the
///   storage and the transport — there is no third-party script in a Flutter
///   app. Saying it out loud is what keeps a future reader from "fixing" this
///   by adding JavaScript-style defences that do not apply.
/// * **Signing out is a server call first, local clear second.** Clearing the
///   cookie locally while the row is still live leaves a token that still
///   works for anyone who captured it; the server has to revoke it, and the
///   local clear is only the follow-up.
library;

import '../../../core/role/app_role.dart';
import '../../../requirement_review/services/api_service.dart';

/// The cookie the server hands out on login, as this device holds it.
class SessionCookie {
  const SessionCookie({required this.name, required this.value});

  /// The server's cookie is `srs_session=<token>`; the name is kept rather
  /// than assumed so a rename on the server surfaces as "no session" instead
  /// of as a request carrying a header nobody reads.
  final String name;
  final String value;

  /// The `Cookie` request header. Only the pair is sent — attributes like
  /// `Path` and `HttpOnly` belong to the response, and echoing them back is a
  /// malformed request that some servers reject.
  String get headerValue => '$name=$value';

  /// Parses the FIRST cookie of a `Set-Cookie` header, ignoring the rest.
  ///
  /// Returns null for a header that is not a cookie at all, and for one with
  /// an empty value (which is how a server clears a cookie — and storing it
  /// would make every later request look signed in with an empty token).
  static SessionCookie? parse(String? rawHeader) {
    if (rawHeader == null) return null;
    final first = rawHeader.split(';').first.trim();
    final index = first.indexOf('=');
    if (index <= 0) return null;
    final name = first.substring(0, index).trim();
    final value = first.substring(index + 1).trim();
    if (name.isEmpty || value.isEmpty) return null;
    return SessionCookie(name: name, value: value);
  }
}

/// Signed in as whom. Null at the top level means "the server said no".
class AccountIdentity {
  const AccountIdentity({
    required this.id,
    required this.username,
    required this.role,
    this.classId,
    this.group,
  });

  factory AccountIdentity.fromJson(Map<String, dynamic> json) =>
      AccountIdentity(
        id: json['id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        role: appRoleFromWire(json['role'] as String? ?? 'student'),
        classId: json['classId'] as String?,
        group: json['group'] as String?,
      );

  final String id;
  final String username;
  final AppRole role;

  /// The teacher's class, or the student's group. Both nullable for the same
  /// reason the server makes them nullable: an account can exist before a
  /// class does, and "not in a class yet" is a state to render, not an error.
  final String? classId;
  final String? group;
}

/// Raised for a sign-in that the server refused. Separate from
/// [ApiException] so the login screen can show "sai tên đăng nhập hoặc mật
/// khẩu" without matching on a status code, and so a NETWORK failure does not
/// get the same message (telling someone their password is wrong when the
/// proxy is merely down is a lie that costs them a retry loop).
class SignInRejected implements Exception {
  const SignInRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to `/auth/*` and remembers the cookie.
class AuthService {
  AuthService(this.api, this.cookieStore);

  final ApiService api;
  final SessionCookieStore cookieStore;

  SessionCookie? _cookie;

  /// The cookie currently held, or null. Exposed for the transport layer to
  /// attach; never for display.
  SessionCookie? get cookie => _cookie;

  /// Asks the server who this device is.
  ///
  /// Returns the identity when the held cookie resolves, and **null when the
  /// server says the session is gone** (401). Any OTHER failure — a dead
  /// proxy, a timeout — is rethrown: collapsing those into null would sign a
  /// user out because their wifi blipped, and they would have to log in again
  /// for no reason.
  Future<AccountIdentity?> whoami() async {
    final stored = await cookieStore.load();
    if (stored == null) return null;
    _cookie = stored;
    try {
      final data = await api.get('/auth/me');
      return AccountIdentity.fromJson(data);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        // The row is gone or expired. Drop the dead cookie so the next request
        // does not carry a token the server already rejected.
        await _forgetLocally();
        return null;
      }
      rethrow;
    }
  }

  /// Signs in, and returns the identity the server confirmed.
  ///
  /// The cookie is only stored AFTER `/auth/me` agrees, which is the same
  /// "a write never trusts its own answer" rule the repositories follow: a
  /// login response body is not proof that the cookie works, and storing a
  /// cookie that does not is how the app lands on a dashboard it cannot load.
  Future<AccountIdentity> signIn({
    required String username,
    required String password,
  }) async {
    final response = await api.rawWrite(
      '/auth/login',
      body: {'username': username.trim(), 'password': password},
    );
    final cookie = SessionCookie.parse(response.headers.value('set-cookie'));
    if (cookie == null) {
      // A 200 without a cookie is a server bug, not a credential problem.
      // Saying so plainly beats an empty dashboard with no explanation.
      throw const SignInRejected(
        'Máy chủ không trả phiên đăng nhập. Kiểm lại cấu hình proxy.',
      );
    }
    await cookieStore.save(cookie);
    _cookie = cookie;
    // `data` is nullable on Dio's Response type; a login that got this far has
    // a 2xx with a body, and treating "no body" as an empty identity would show
    // a nameless account instead of failing. `?? const {}` keeps it total
    // without inventing fields.
    final data = response.data ?? const <String, dynamic>{};
    return AccountIdentity(
      id: data['id'] as String? ?? '',
      username: data['username'] as String? ?? username,
      role: appRoleFromWire(data['role'] as String? ?? 'student'),
      classId: data['classId'] as String?,
      group: data['group'] as String?,
    );
  }

  /// Registers, then signs in.
  ///
  /// Two calls on purpose. The register route answers 201 with the new account
  /// and NO session (a teacher must not be able to mint a session for somebody
  /// else's name), so a caller that wanted to be signed in afterwards has to
  /// prove it holds the password — which is what the second call does. Merging
  /// them would hide the case where the second fails and the account exists.
  Future<AccountIdentity> register({
    required String username,
    required String password,
    required AppRole role,
    String? classId,
    String? group,
  }) async {
    await api.rawWrite(
      '/auth/register',
      body: {
        'username': username.trim(),
        'password': password,
        'role': role.wire,
        if (classId != null && classId.trim().isNotEmpty)
          'class_id': classId.trim(),
        if (group != null && group.trim().isNotEmpty) 'group': group.trim(),
      },
    );
    return signIn(username: username, password: password);
  }

  /// Revokes the session on the SERVER, then forgets it here.
  ///
  /// Order matters and is the reason this is not just "clear local state": a
  /// locally-forgotten cookie whose row is still live is a working credential
  /// left behind. If the revoke call fails the local clear still happens —
  /// refusing to sign out because the network is down would hold a user in a
  /// session they asked to leave — but the failure is not reported as success
  /// by the caller's screen, which shows the login form either way.
  Future<void> signOut() async {
    try {
      await api.rawWrite('/auth/logout');
    } on ApiException {
      // Best effort: the server sweeps expired rows, and the local token is
      // gone below, so the worst case is one row living out its TTL.
    } finally {
      await _forgetLocally();
    }
  }

  Future<void> _forgetLocally() async {
    _cookie = null;
    await cookieStore.clear();
  }
}

/// Where the cookie lives between launches.
///
/// An interface so a test injects memory, the same shape as the feature
/// stores. Note what is NOT here: no expiry bookkeeping. The server owns the
/// TTL, and a client that also expired the cookie would drift from it — a
/// client clock that is wrong would sign people out early or hold a dead token.
abstract interface class SessionCookieStore {
  Future<SessionCookie?> load();
  Future<void> save(SessionCookie cookie);
  Future<void> clear();
}

class MemorySessionCookieStore implements SessionCookieStore {
  SessionCookie? _cookie;

  @override
  Future<SessionCookie?> load() async => _cookie;

  @override
  Future<void> save(SessionCookie cookie) async => _cookie = cookie;

  @override
  Future<void> clear() async => _cookie = null;
}
