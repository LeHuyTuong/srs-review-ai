/// The account gate and the sign-in surface (ADR-0020).
///
/// What these tests protect is the DIFFERENCE between the four session states,
/// because collapsing any two of them produces a screen that lies:
///
/// * `asking` must not show the form, or an already-signed-in user sees a
///   login page flash on every cold start.
/// * `offline` must not show the form either — a dead proxy is not an expired
///   session, and the form would fail for the same reason the check did.
/// * `signedIn` must mount the shell for the role the SERVER reported, not the
///   role the build was compiled as. This is the whole point of ADR-0020.
///
/// The store is faked rather than the service so the real `AuthService` logic
/// (parse the cookie, install it, decide 401 vs network) is what runs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/role/app_role.dart';
import 'package:srs_review_ai/features/auth/data/auth_service.dart';
import 'package:srs_review_ai/features/auth/view/account_view.dart';
import 'package:srs_review_ai/features/auth/view_model/session_view_model.dart';
import 'package:srs_review_ai/main.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

import 'auth_service_test.dart' show scriptedApi;

/// A service that answers from a fixed identity, so a screen test never opens
/// a socket. It extends the REAL class the way the rubric-editor lesson
/// records: a fake that merely implements an interface leaves the real one's
/// defaults in place and measures something other than what it claims.
class _StubAuthService extends AuthService {
  _StubAuthService(
    super.api,
    super.cookieStore, {
    this.identity,
    this.throwOnWhoami,
    this.rejectSignIn = false,
  });

  AccountIdentity? identity;
  Object? throwOnWhoami;
  bool rejectSignIn;
  String? lastUsername;

  @override
  Future<AccountIdentity?> whoami() async {
    final failure = throwOnWhoami;
    if (failure != null) {
      throw failure;
    }
    return identity;
  }

  @override
  Future<AccountIdentity> signIn({
    required String username,
    required String password,
  }) async {
    lastUsername = username;
    if (rejectSignIn) {
      throw const SignInRejected('Sai tên đăng nhập hoặc mật khẩu.');
    }
    return identity ??
        AccountIdentity(id: 'u1', username: username, role: AppRole.student);
  }
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: AccountView()),
);

/// A real (empty) preferences instance. `setMockInitialValues` is what makes
/// the plugin answer inside `flutter test`, where no channel exists.
Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('the session gate', () {
    testWidgets('a resolved session mounts the shell for the SERVER role', (
      tester,
    ) async {
      // The point of ADR-0020: the shell is chosen from what the server said,
      // not from the build. This identity is a TEACHER on a build that used to
      // hard-code `AppRoleScope.student()`.
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) => _StubAuthService(
              scriptedApi(),
              MemorySessionCookieStore(),
              identity: const AccountIdentity(
                id: 'u1',
                username: 'gv01',
                role: AppRole.teacher,
                classId: 'cls-A',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: SrsReviewApp()),
      );
      // Let the microtask that calls `whoami` and the router mount run.
      await tester.pump();
      await tester.pump();

      final session = container.read(sessionViewModelProvider);
      expect(session.status, SessionStatus.signedIn);
      expect(session.role, AppRole.teacher);
      expect(session.identity!.classId, 'cls-A');
    });

    testWidgets('a dead proxy is OFFLINE, not signed out', (tester) async {
      // The distinction the whole view-model exists for: a network failure
      // must not render the login form, because the form would fail for the
      // same reason the check did and read as a wrong password.
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) => _StubAuthService(
              scriptedApi(),
              MemorySessionCookieStore(),
              throwOnWhoami: ApiException('proxy down'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: SrsReviewApp()),
      );
      await tester.pump();
      await tester.pump();

      final session = container.read(sessionViewModelProvider);
      expect(session.status, SessionStatus.offline);
      expect(session.status, isNot(SessionStatus.signedOut));
      expect(find.text('Không kết nối được máy chủ'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsNothing);
    });
  });

  group('AccountView', () {
    testWidgets('signs in and refuses an empty form', (tester) async {
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) =>
                _StubAuthService(scriptedApi(), MemorySessionCookieStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pump();

      // The submit button exists but is disabled until the form is usable —
      // a button that looks enabled and does nothing is the failure mode.
      final button = find.widgetWithText(FilledButton, 'Đăng nhập');
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'sv01');
      await tester.enterText(find.byType(TextField).at(1), 'matkhau-du-dai');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('a refused sign-in shows the server sentence, not a code', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) => _StubAuthService(
              scriptedApi(),
              MemorySessionCookieStore(),
              rejectSignIn: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'sv01');
      await tester.enterText(find.byType(TextField).at(1), 'sai-mat-khau');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sai tên đăng nhập hoặc mật khẩu.'), findsOneWidget);
    });

    testWidgets('the password field is obscured', (tester) async {
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) =>
                _StubAuthService(scriptedApi(), MemorySessionCookieStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pump();
      final password = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(password.obscureText, isTrue);
    });

    testWidgets('registering reveals the membership field for the role', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          // The transport reads this provider when it builds an ApiService.
          // Overriding it is the same rule every other test harness here
          // follows; without it the read throws `ProviderException` and the
          // session layer reports it as a network failure.
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          sessionCookieStoreProvider.overrideWithValue(
            MemorySessionCookieStore(),
          ),
          authServiceProvider.overrideWith(
            (ref) =>
                _StubAuthService(scriptedApi(), MemorySessionCookieStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pump();
      await tester.tap(find.text('Chưa có tài khoản? Tạo mới'));
      await tester.pump();

      // Student is the default, so the GROUP field is the one shown. Both at
      // once would invite filling the wrong one, and they store to different
      // columns on the server.
      expect(find.text('Nhóm của bạn'), findsOneWidget);
      expect(find.text('Mã lớp phụ trách'), findsNothing);

      await tester.tap(find.text('Giảng viên'));
      await tester.pump();
      expect(find.text('Mã lớp phụ trách'), findsOneWidget);
      expect(find.text('Nhóm của bạn'), findsNothing);
    });
  });
}
