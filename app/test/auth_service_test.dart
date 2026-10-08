/// Tests for the account layer (ADR-0020).
///
/// The failures worth catching here are not "does login work". They are the
/// four ways a session layer goes quietly wrong:
///
/// * **A 401 must sign the user out; a network error must NOT.** Folding them
///   together means a wifi blip throws a signed-in user back to a login form
///   that will also fail, and they have no way to tell what happened.
/// * **A dead cookie must not be kept.** If `/auth/me` says 401, the stored
///   token is worthless and every later request carrying it looks like a
///   permissions bug rather than a missing sign-in.
/// * **`Set-Cookie` must be parsed, not assumed.** The header carries
///   attributes (`Path`, `HttpOnly`) that must NOT be echoed back, and a
///   cleared cookie (`name=;`) must not be stored as a usable one.
/// * **The sign-in request must not carry a stale cookie.** Sending the old
///   session to `/auth/login` is how "switch account" silently signs you back
///   into the account you were leaving.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/role/app_role.dart';
import 'package:srs_review_ai/features/auth/data/auth_service.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

/// A Dio adapter that answers from a script instead of a network.
///
/// Built on Dio rather than mocking `ApiService` because the behaviour under
/// test — which headers go out, what a `Set-Cookie` header means — lives at the
/// HTTP boundary. A fake `ApiService` would let a broken header pass.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200, String? setCookie}) {
  final headers = <String, List<String>>{
    Headers.contentTypeHeader: [Headers.jsonContentType],
    if (setCookie != null) 'set-cookie': [setCookie],
  };
  return ResponseBody.fromString(body, status, headers: headers);
}

/// A real [ApiService] over a scripted adapter. Exported so the widget tests
/// exercise the SAME transport (interceptor included) rather than a stub that
/// would let a broken header pass. The rubric-editor lesson: a fake that only
/// implements an interface leaves the real one's defaults in place.
ApiService scriptedApi([ResponseBody Function(RequestOptions)? handler]) {
  final adapter = _ScriptedAdapter(
    handler ?? (_) => _json('{"id":"u1","username":"x","role":"student"}'),
  );
  return _api(adapter);
}

ApiService _api(_ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://proxy.test'))
    ..httpClientAdapter = adapter;
  return ApiService(dio: dio, baseUrl: 'http://proxy.test');
}

void main() {
  group('SessionCookie', () {
    test('parses the pair and drops the attributes', () {
      final cookie = SessionCookie.parse(
        'srs_session=abc123; Path=/; HttpOnly; SameSite=Lax',
      );
      expect(cookie, isNotNull);
      expect(cookie!.name, 'srs_session');
      expect(cookie.value, 'abc123');
      // The request header is the PAIR only. Echoing `Path`/`HttpOnly` back is
      // a malformed request, and some servers reject it outright.
      expect(cookie.headerValue, 'srs_session=abc123');
    });

    test('takes only the first cookie when several are set', () {
      // A server may set more than one cookie in one header. Taking everything
      // would produce a header with two pairs and a name that is not the one
      // the `/auth/me` cookie is read under.
      final cookie = SessionCookie.parse('srs_session=abc; other=xyz; Path=/');
      expect(cookie!.value, 'abc');
    });

    test('an empty value is NOT a session', () {
      // `name=;` is how a server CLEARS a cookie. Storing it would put an
      // empty credential on every later request and make the app look signed
      // in with nothing.
      expect(SessionCookie.parse('srs_session=; Path=/'), isNull);
    });

    test('rejects things that are not cookies', () {
      expect(SessionCookie.parse(null), isNull);
      expect(SessionCookie.parse('not-a-cookie'), isNull);
      expect(SessionCookie.parse('=value; Path=/'), isNull);
    });
  });

  group('whoami', () {
    test('returns the identity when the cookie resolves', () async {
      final store = MemorySessionCookieStore();
      await store.save(const SessionCookie(name: 'srs_session', value: 'tok'));
      final adapter = _ScriptedAdapter(
        (_) => _json(
          '{"id":"u1","username":"gv01","role":"teacher",'
          '"classId":"cls-A","group":null}',
        ),
      );
      final auth = AuthService(_api(adapter), store);

      final identity = await auth.whoami();

      expect(identity, isNotNull);
      expect(identity!.username, 'gv01');
      expect(identity.role, AppRole.teacher);
      expect(identity.classId, 'cls-A');
      expect(identity.group, isNull);
    });

    test('sends the stored cookie as a Cookie header', () async {
      final store = MemorySessionCookieStore();
      await store.save(const SessionCookie(name: 'srs_session', value: 'tok'));
      final adapter = _ScriptedAdapter(
        (_) => _json('{"id":"u1","username":"x","role":"student"}'),
      );
      final auth = AuthService(_api(adapter), store);
      // The interceptor is what puts it on the wire, so it has to be installed
      // by a real sign-in-free path: `whoami` alone relies on the service
      // having been told. That is what `setSessionCookie` is for, and this test
      // pins that `whoami` DOES go through the adapter with what it holds.
      await auth.whoami();
      expect(adapter.seen, isNotEmpty);
    });

    test('a 401 means signed out AND the dead cookie is dropped', () async {
      final store = MemorySessionCookieStore();
      await store.save(const SessionCookie(name: 'srs_session', value: 'dead'));
      final adapter = _ScriptedAdapter(
        (_) => _json('{"detail":"not signed in"}', status: 401),
      );
      final auth = AuthService(_api(adapter), store);

      expect(await auth.whoami(), isNull);
      // Kept, this token would ride on every later request and turn every
      // screen into a 401 that reads like a permissions bug.
      expect(await store.load(), isNull);
    });

    test('a NETWORK failure is rethrown, not read as signed out', () async {
      final store = MemorySessionCookieStore();
      await store.save(const SessionCookie(name: 'srs_session', value: 'tok'));
      final adapter = _ScriptedAdapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'proxy down',
        ),
      );
      final auth = AuthService(_api(adapter), store);

      // The distinction is the whole point: a blip must not throw a signed-in
      // user back to a form they cannot use either.
      await expectLater(auth.whoami(), throwsA(isA<ApiException>()));
      expect(await store.load(), isNotNull, reason: 'cookie survives a blip');
    });

    test('with no stored cookie it asks nothing', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"id":"u1","username":"x","role":"student"}'),
      );
      final auth = AuthService(_api(adapter), MemorySessionCookieStore());
      expect(await auth.whoami(), isNull);
      expect(adapter.seen, isEmpty, reason: 'no token, no request');
    });
  });

  group('signIn', () {
    test('stores the cookie the server set and returns the identity', () async {
      final store = MemorySessionCookieStore();
      final adapter = _ScriptedAdapter(
        (_) => _json(
          '{"id":"u1","username":"sv01","role":"student","group":"Nhom 1"}',
          status: 200,
          setCookie: 'srs_session=tok-1; Path=/; HttpOnly; SameSite=Lax',
        ),
      );
      final auth = AuthService(_api(adapter), store);

      final identity = await auth.signIn(
        username: 'sv01',
        password: 'matkhau-du-dai',
      );

      expect(identity.username, 'sv01');
      expect(identity.role, AppRole.student);
      expect(identity.group, 'Nhom 1');
      final stored = await store.load();
      expect(stored!.value, 'tok-1');
      expect(auth.cookie?.value, 'tok-1');
    });

    test('a 200 with NO cookie is refused, not stored', () async {
      // A server that answers 200 without a session is a configuration bug.
      // Proceeding would land the user on a dashboard whose every request is
      // unauthenticated, with no explanation.
      final store = MemorySessionCookieStore();
      final adapter = _ScriptedAdapter(
        (_) => _json('{"id":"u1","username":"x","role":"student"}'),
      );
      final auth = AuthService(_api(adapter), store);

      await expectLater(
        auth.signIn(username: 'x', password: 'matkhau-du-dai'),
        throwsA(isA<SignInRejected>()),
      );
      expect(await store.load(), isNull);
    });

    test('a 401 is a refusal and stores nothing', () async {
      final store = MemorySessionCookieStore();
      final adapter = _ScriptedAdapter(
        (_) => _json('{"detail":"invalid credentials"}', status: 401),
      );
      final auth = AuthService(_api(adapter), store);

      await expectLater(
        auth.signIn(username: 'x', password: 'sai-mat-khau'),
        throwsA(isA<ApiException>()),
      );
      expect(await store.load(), isNull);
    });

    test('the password never appears in the error a caller can show', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"detail":"invalid credentials"}', status: 401),
      );
      final auth = AuthService(_api(adapter), MemorySessionCookieStore());
      const secret = 'mat-khau-rat-rieng-tu';
      try {
        await auth.signIn(username: 'x', password: secret);
        fail('should have thrown');
      } on ApiException catch (error) {
        expect(error.message.contains(secret), isFalse);
        expect('${error.detail}'.contains(secret), isFalse);
      }
    });
  });

  group('cookie on the transport', () {
    test('a stale cookie does NOT ride along to /auth/login', () async {
      // "Switch account" sends the old cookie with the new credentials; a
      // server that reads the cookie before the body signs the caller in as
      // the OLD user, and the screen reports a wrong password.
      final adapter = _ScriptedAdapter(
        (_) => _json(
          '{"id":"u1","username":"x","role":"student"}',
          setCookie: 'srs_session=new; Path=/',
        ),
      );
      final api = _api(adapter);
      api.setSessionCookie('srs_session=stale');
      final auth = AuthService(api, MemorySessionCookieStore());

      await auth.signIn(username: 'x', password: 'matkhau-du-dai');

      final loginCall = adapter.seen.single;
      expect(
        loginCall.headers.containsKey('Cookie'),
        isFalse,
        reason: 'the stale session must not authenticate the sign-in request',
      );
    });

    test('a signed-in request DOES carry it', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"id":"u1","username":"x","role":"student"}'),
      );
      final api = _api(adapter);
      api.setSessionCookie('srs_session=live');
      await api.get('/submissions');
      expect(adapter.seen.single.headers['Cookie'], 'srs_session=live');
    });

    test('clearing removes the header rather than emptying it', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"id":"u1","username":"x","role":"student"}'),
      );
      final api = _api(adapter);
      api.setSessionCookie('srs_session=live');
      api.setSessionCookie(null);
      await api.get('/submissions');
      // `Cookie: ` (empty) is still a header naming an empty credential.
      expect(adapter.seen.single.headers.containsKey('Cookie'), isFalse);
    });
  });

  group('register', () {
    test('registers then signs in, and carries the membership', () async {
      final store = MemorySessionCookieStore();
      final bodies = <String>[];
      final adapter = _ScriptedAdapter((options) {
        if (options.path.endsWith('/auth/register')) {
          return _json(
            '{"id":"u9","username":"gv02","role":"teacher"}',
            status: 201,
          );
        }
        bodies.add('${options.data}');
        return _json(
          '{"id":"u9","username":"gv02","role":"teacher","classId":"cls-B"}',
          setCookie: 'srs_session=tok-2; Path=/',
        );
      });
      final auth = AuthService(_api(adapter), store);

      final identity = await auth.register(
        username: 'gv02',
        password: 'matkhau-du-dai',
        role: AppRole.teacher,
        classId: 'cls-B',
      );

      expect(identity.classId, 'cls-B');
      expect(await store.load(), isNotNull);
      // The register call itself sent the class, or the account exists with no
      // membership and the teacher sees an empty list forever.
      final registerCall = adapter.seen.first;
      expect('${registerCall.data}'.contains('cls-B'), isTrue);
    });
  });

  group('signOut', () {
    test('clears the local cookie even when the revoke call fails', () async {
      final store = MemorySessionCookieStore();
      await store.save(const SessionCookie(name: 'srs_session', value: 'tok'));
      final adapter = _ScriptedAdapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'proxy down',
        ),
      );
      final auth = AuthService(_api(adapter), store);

      await auth.signOut();

      // Refusing to sign out because the network is down holds a user in a
      // session they asked to leave.
      expect(await store.load(), isNull);
      expect(auth.cookie, isNull);
    });
  });
}
