/// Dependency wiring. One place, so swapping the real proxy for the offline
/// mock is a single provider override.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../deterministic_checks/checks/rubric_config.dart';
import '../deterministic_checks/models/ai_criterion.dart';
import '../diagram_audit/services/page_image_renderer.dart';
import '../document_import/repositories/document_repository.dart';
import '../document_import/services/document_map_service.dart';
import '../requirement_review/repositories/review_repository.dart';
import '../requirement_review/services/api_service.dart';
import '../requirement_review/services/mock_review_api.dart';
import '../requirement_review/services/review_api.dart';
import '../review_history/services/session_store.dart';
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

/// The editable AI evaluation checklist (2026-09-25).
///
/// This is DATA on the proxy (`/criteria`), not a const list in the app — the
/// row a user switches off here is the row the model stops being asked about,
/// because `prompt.py` renders whatever the store has enabled. The offline
/// rule-based checks in `data/checks/` are deliberately NOT in this list: they
/// are exact, free, and shown on their own dashboard section.
/// Writes to the marking scale (2026-09-25).
///
/// `rubricProvider` above stays the READ path — it already has the offline
/// fallback and the whole UI depends on it. This is only the write path, and it
/// invalidates the reader after a successful save so the two can never disagree
/// about what the proxy is serving.
///
/// The scale is not free-form: the proxy refuses a weight set that does not sum
/// to 1.0, and a reweighting has to be sent whole (see `rubric_store.py`). This
/// controller therefore forwards one patch and reports the proxy's own refusal
/// instead of pre-judging it — the client is not a second place where the rule
/// lives.
final rubricControllerProvider =
    AsyncNotifierProvider<RubricController, RubricConfig>(RubricController.new);

class RubricController extends AsyncNotifier<RubricConfig> {
  ApiService? get _api {
    final candidate = ref.read(reviewApiProvider);
    return candidate is ApiService ? candidate : null;
  }

  bool get canEdit => _api != null;

  @override
  Future<RubricConfig> build() async => RubricConfig.fallback;

  Future<String?> save(Map<String, dynamic> patch) async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được chuẩn khi đang kết nối máy chủ.';
    try {
      final served = await api.updateRubric(patch);
      // Render what the proxy now serves, not what we sent: it validates and
      // may normalise, and the report has to quote the live scale.
      state = AsyncData(served);
      ref.invalidate(rubricProvider);
      return null;
    } on Object catch (error) {
      return error is ApiException ? error.message : 'Không lưu được: $error';
    }
  }

  Future<String?> resetToSeed() async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được chuẩn khi đang kết nối máy chủ.';
    try {
      state = AsyncData(await api.resetRubric());
      ref.invalidate(rubricProvider);
      return null;
    } on Object catch (error) {
      return error is ApiException
          ? error.message
          : 'Không khôi phục được: $error';
    }
  }
}

final criteriaProvider =
    AsyncNotifierProvider<CriteriaController, List<AiCriterion>>(
      CriteriaController.new,
    );

class CriteriaController extends AsyncNotifier<List<AiCriterion>> {
  /// Null in mock mode: there is no proxy to ask, and pretending otherwise
  /// would show a checklist the review would not use.
  ApiService? get _api {
    final candidate = ref.read(reviewApiProvider);
    return candidate is ApiService ? candidate : null;
  }

  bool get canEdit => _api != null;

  @override
  Future<List<AiCriterion>> build() async {
    final api = _api;
    if (api == null) return const [];
    try {
      return await api.fetchCriteria();
    } on Object {
      // An unreachable proxy must not block the screen; the view shows the
      // error state and the retry button.
      rethrow;
    }
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(api.fetchCriteria);
  }

  /// Flips one row. Returns null on success or a message to show — the view
  /// owns the SnackBar, this stays free of BuildContext.
  Future<String?> setEnabled(AiCriterion criterion, bool enabled) async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được tiêu chí khi đang kết nối máy chủ.';
    try {
      await api.updateCriterion(criterion.id, {'enabled': enabled});
      await _reload();
      return null;
    } on Object catch (error) {
      return _message(error);
    }
  }

  /// Creates when [existing] is null, updates otherwise.
  Future<String?> save({
    AiCriterion? existing,
    required String id,
    required String title,
    required String what,
    required CriterionScope scope,
    required CriterionSeverity severity,
    required String source,
    required int order,
  }) async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được tiêu chí khi đang kết nối máy chủ.';
    if (title.trim().isEmpty) return 'Tiêu đề không được để trống.';
    if (what.trim().isEmpty) return 'Phần mô tả kiểm tra không được để trống.';
    if (existing == null && !_validId(id)) {
      return 'Mã tiêu chí chỉ gồm chữ thường, số, dấu gạch và dấu chấm.';
    }
    try {
      if (existing == null) {
        await api.createCriterion(
          AiCriterion(
            id: id,
            title: title.trim(),
            what: what.trim(),
            source: source.trim(),
            scope: scope,
            severity: severity,
            order: order,
          ),
        );
      } else {
        await api.updateCriterion(existing.id, {
          'title': title.trim(),
          'what': what.trim(),
          'source': source.trim(),
          'scope': scope.wire,
          'severity': severity.name,
          'order': order,
        });
      }
      await _reload();
      return null;
    } on Object catch (error) {
      return _message(error);
    }
  }

  Future<String?> remove(String id) async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được tiêu chí khi đang kết nối máy chủ.';
    try {
      await api.deleteCriterion(id);
      await _reload();
      return null;
    } on Object catch (error) {
      return _message(error);
    }
  }

  Future<String?> resetToSeed() async {
    final api = _api;
    if (api == null) return 'Chỉ sửa được tiêu chí khi đang kết nối máy chủ.';
    try {
      await api.resetCriteria();
      await _reload();
      return null;
    } on Object catch (error) {
      return _message(error);
    }
  }

  Future<void> _reload() async {
    final api = _api;
    if (api == null) return;
    state = AsyncData(await api.fetchCriteria());
  }

  static bool _validId(String id) =>
      RegExp(r'^[a-z0-9][a-z0-9_.-]*$').hasMatch(id);

  /// The proxy's own message when it has one — "criterion 'x' already exists"
  /// tells the user what to do, "request failed" does not.
  static String _message(Object error) {
    if (error is ApiException) return error.message;
    return 'Không lưu được tiêu chí: $error';
  }
}

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
