/// Build-time configuration.
///
/// Everything here is a `--dart-define`, never a committed literal. The app
/// holds NO LLM credential of any kind — `tools/check_guardrails.py` fails the
/// build if a provider URL or an API key ever appears under `app/lib`.
library;

import 'dart:io' show Platform;

class AppConfig {
  const AppConfig._();

  /// Where the FastAPI proxy lives.
  ///
  /// Android emulators cannot reach the host through `localhost`; 10.0.2.2 is
  /// the emulator's alias for it. Override explicitly on a physical device:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// Demo safety net: skip the network entirely and serve bundled fixtures.
  static const bool forceMockMode = bool.fromEnvironment('MOCK_MODE');

  // No Syncfusion licence key is configured on purpose. Verified in
  // syncfusion_flutter_core 34.2.7 CHANGELOG: "The license key is not required
  // now to run the application with our widgets" — so there is no trial banner
  // to worry about at the defense. A Community Licence is still legally
  // required; see docs/adr/0003-syncfusion-licence.md.

  static const Duration requestTimeout = Duration(seconds: 90);
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Client-side guard so a stray loop cannot burn the free-tier quota.
  static const int maxRequirementsPerRun = 40;
}
