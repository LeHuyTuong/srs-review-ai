/// Settings → Proxy URL override: persistence through SharedPreferences and
/// its effect on the review API wiring.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/data/services/api_service.dart';

void main() {
  // SharedPreferences plugin needs a mock channel in unit tests.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    return c;
  }

  test('no saved url means null (build-time default stays in charge)', () async {
    final c = await container();
    addTearDown(c.dispose);
    expect(c.read(proxyUrlProvider), isNull);
  });

  test('set() persists and survives a fresh container', () async {
    final c = await container();
    addTearDown(c.dispose);
    c.read(proxyUrlProvider.notifier).set(' http://192.168.1.20:8000 ');

    // A brand-new container (fresh notifier, same prefs) sees the saved url.
    final prefs = await SharedPreferences.getInstance();
    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(proxyUrlProvider), 'http://192.168.1.20:8000');
  });

  test('clearing the field falls back to the build-time default', () async {
    final c = await container();
    addTearDown(c.dispose);
    final notifier = c.read(proxyUrlProvider.notifier);
    notifier.set('http://10.0.0.5:8000');
    notifier.set('');
    expect(c.read(proxyUrlProvider), isNull);
  });

  test('review api uses the overridden base url', () async {
    final c = await container();
    addTearDown(c.dispose);
    c.read(proxyUrlProvider.notifier).set('http://192.168.1.20:8000');

    // Leave mock mode off so the real ApiService is wired.
    expect(c.read(mockModeProvider), isFalse);
    final api = c.read(reviewApiProvider);
    expect(api, isA<ApiService>());
    expect((api as ApiService).effectiveBaseUrl, 'http://192.168.1.20:8000');
  });
}
