/// Dependency wiring. One place, so swapping the real proxy for the offline
/// mock is a single provider override.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/checks/rubric_config.dart';
import '../data/repositories/document_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/services/api_service.dart';
import '../data/services/document_map_service.dart';
import '../data/services/mock_review_api.dart';
import '../data/services/page_image_renderer.dart';
import '../data/services/review_api.dart';
import '../data/services/session_store.dart';
import 'app_config.dart';

/// Runtime demo switch. Starts from the build-time flag but stays flippable on
/// stage: pulling the WiFi plug should not end the demo.
///
/// A [Notifier] rather than `StateProvider`, which Riverpod 3 moved to
/// `legacy.dart`.
class MockModeNotifier extends Notifier<bool> {
  @override
  bool build() => AppConfig.forceMockMode;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

final mockModeProvider = NotifierProvider<MockModeNotifier, bool>(
  MockModeNotifier.new,
);

const String _kProxyUrlKey = 'srs.proxy.url';

/// The review proxy URL the user typed in Settings, persisted across runs.
/// `null` means "use the build-time default" (see [AppConfig.apiBaseUrl]) —
/// this is what makes a phone build able to point at a laptop running
/// `uvicorn` on the same WiFi without rebuilding the app.
class ProxyUrlNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Tests that only override sessionStoreProvider never provide
    // SharedPreferences; treat that as "no saved URL" instead of exploding
    // the whole review pipeline.
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      return prefs.getString(_kProxyUrlKey);
    } on UnimplementedError {
      return null;
    }
  }

  void set(String? value) {
    // `ref.read`, not `ref.watch`: this runs outside `build()`, where a watch
    // would quietly open a dependency the notifier never re-evaluates.
    final prefs = ref.read(sharedPreferencesProvider);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      prefs.remove(_kProxyUrlKey);
      state = null;
      return;
    }
    prefs.setString(_kProxyUrlKey, trimmed);
    state = trimmed;
  }
}

final proxyUrlProvider = NotifierProvider<ProxyUrlNotifier, String?>(
  ProxyUrlNotifier.new,
);

const String _kAppTokenKey = 'srs.proxy.appToken';
const String _kUserIdKey = 'srs.proxy.userId';

/// The shared secret the proxy expects in `X-App-Token`.
///
/// The server disables auth while `APP_TOKEN` is empty, so this stays empty on
/// a localhost demo. The moment somebody deploys the proxy and sets that env
/// var, every request without a matching header is a 401 — previously the app
/// had no way to supply one, which made the auth path dead on arrival.
class AppTokenNotifier extends Notifier<String?> {
  @override
  String? build() {
    try {
      return ref.watch(sharedPreferencesProvider).getString(_kAppTokenKey);
    } on UnimplementedError {
      return null;
    }
  }

  void set(String? value) {
    final prefs = ref.read(sharedPreferencesProvider);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      prefs.remove(_kAppTokenKey);
      state = null;
      return;
    }
    prefs.setString(_kAppTokenKey, trimmed);
    state = trimmed;
  }
}

final appTokenProvider = NotifierProvider<AppTokenNotifier, String?>(
  AppTokenNotifier.new,
);

/// A stable, anonymous, per-install identifier sent as `X-User-Id`.
///
/// Not a login and not personal data — just enough for the proxy's per-user
/// rate limiter to distinguish one device from another. Without it every
/// request collapses onto the caller's IP, so one shared network would drain a
/// whole day's quota for everyone on it.
class UserIdNotifier extends Notifier<String> {
  @override
  String build() {
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      final existing = prefs.getString(_kUserIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = _generate();
      prefs.setString(_kUserIdKey, generated);
      return generated;
    } on UnimplementedError {
      return 'unidentified-device';
    }
  }

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

final userIdProvider = NotifierProvider<UserIdNotifier, String>(
  UserIdNotifier.new,
);

final reviewApiProvider = Provider<ReviewApi>((ref) {
  if (ref.watch(mockModeProvider)) return const MockReviewApi();
  return ApiService(
    baseUrl: ref.watch(proxyUrlProvider),
    appToken: ref.watch(appTokenProvider),
    userId: ref.watch(userIdProvider),
  );
});

/// Whether the configured proxy can actually be reached right now.
///
/// The UI used to infer connectivity from the offline toggle alone, so an app
/// pointed at a dead proxy still showed "Online" — and a run that returned
/// zero findings looked like a clean document rather than a broken connection.
/// This asks the proxy instead of assuming.
final proxyStatusProvider = FutureProvider<bool?>((ref) async {
  if (ref.watch(mockModeProvider)) return null; // mock mode: not applicable
  final api = ref.watch(reviewApiProvider);
  return api.isProxyUp();
});

/// Rubric thresholds, straight from the proxy. Falls back to the committed
/// copy so the app still knows the syllabus numbers offline.
final rubricProvider = FutureProvider<RubricConfig>((ref) async {
  final api = ref.watch(reviewApiProvider);
  try {
    return await api.fetchRubric();
  } on Object {
    return RubricConfig.fallback;
  }
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  // AsyncValue.value is nullable in Riverpod 3 (there is no valueOrNull).
  return DocumentRepository(
    rubric: ref.watch(rubricProvider).value ?? RubricConfig.fallback,
  );
});

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(
    ref.watch(reviewApiProvider),
    renderer: PageImageRenderer(),
  ),
);

/// Server document-anatomy client (`/documents/analyze` + `/documents/render`).
///
/// Null in mock mode — there is no proxy to upload to, and the heuristic
/// parse path is exactly what mock mode exists to exercise. Online, the
/// workspace uploads the imported file once and every figure-aware feature
/// (vision audit crops, truthful diagram-page counts) reads from the map.
final documentMapServiceProvider = Provider<DocumentMapService?>((ref) {
  if (ref.watch(mockModeProvider)) return null;
  return DocumentMapService(
    baseUrl: ref.watch(proxyUrlProvider),
    appToken: ref.watch(appTokenProvider),
  );
});

/// Overridden in `main()` with the instance awaited before `runApp`, so the
/// session store can read the draft synchronously from the first build.
/// Tests override [sessionStoreProvider] with an in-memory store instead.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

/// The history store. `main()` overrides this with whichever backend the
/// platform can actually run (`openSessionStore` prefers the embedded database
/// and falls back to `shared_preferences`); the default below keeps every test
/// and any bare `ProviderScope` working without a database.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SharedPreferencesSessionStore(ref.watch(sharedPreferencesProvider)),
);
