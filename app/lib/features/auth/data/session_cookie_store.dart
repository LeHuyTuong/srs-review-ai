/// Where the session cookie lives on the device (ADR-0020).
///
/// Split out of `auth_service.dart` for the reason the guardrail enforces and
/// not merely to satisfy it: the ONLY file allowed to touch
/// `shared_preferences` is the one whose whole job is holding an instance of
/// it. `auth_service.dart` talks to `/auth/*` and should be constructible from
/// a fake cookie store with no plugin in sight — which is exactly what its
/// tests do.
///
/// The parse failure rule matches the other stores: a blob nobody can read
/// means "sign in again", so it starts over rather than bricking the app.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// The production store, on the device's preferences.
///
/// Reads are synchronous under the hood (the plugin was already awaited by
/// `sharedPreferencesProvider`), so this mirrors the feature stores rather than
/// inventing a second async story.
///
/// A corrupt blob starts over instead of throwing, the same rule the student
/// and teacher stores follow: a cookie nobody can parse means "sign in again",
/// and bricking the app on it is strictly worse than asking.
class SharedPreferencesSessionCookieStore implements SessionCookieStore {
  SharedPreferencesSessionCookieStore(this._prefs);

  final SharedPreferences _prefs;

  static const String cookieKey = 'srs.auth.cookie';

  @override
  Future<SessionCookie?> load() async {
    final raw = _prefs.getString(cookieKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final row = Map<String, dynamic>.from(
        jsonDecode(raw) as Map<dynamic, dynamic>,
      );
      final name = row['name'] as String? ?? '';
      final value = row['value'] as String? ?? '';
      if (name.isEmpty || value.isEmpty) return null;
      return SessionCookie(name: name, value: value);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(SessionCookie cookie) async => _prefs.setString(
    cookieKey,
    jsonEncode({'name': cookie.name, 'value': cookie.value}),
  );

  @override
  Future<void> clear() async => _prefs.remove(cookieKey);
}

/// Opens the production cookie store.
SessionCookieStore openSessionCookieStore(SharedPreferences prefs) =>
    SharedPreferencesSessionCookieStore(prefs);
