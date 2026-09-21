/// Build-time configuration.
///
/// Everything here is a `--dart-define`, never a committed literal. The app
/// holds NO LLM credential of any kind — `tools/check_guardrails.py` fails the
/// build if a provider URL or an API key ever appears under `app/lib`.
library;

// `dart:io` is deliberately not imported: it does not compile for web, and
// Chrome is the fastest way to eyeball the UI during development.
// `defaultTargetPlatform` covers every target from one import.
import 'package:flutter/foundation.dart';

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
    // kIsWeb must be tested first: in Chrome, defaultTargetPlatform reports
    // the *host* OS, so a browser on Android would otherwise pick 10.0.2.2.
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
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
  ///
  /// Kept EQUAL to the proxy's `rate_limit_per_day`
  /// (`server/app/config.py`, 50). It was 60 for a while and every run of
  /// more than 50 units then hit 429 part-way through: the quota was spent,
  /// the run died, and the user was left with "Thất bại" on every row and no
  /// reason anywhere on screen. The client must never promise more units per
  /// run than the server will actually serve.
  static const int maxRequirementsPerRun = 50;

  /// How many requirements are reviewed at once.
  ///
  /// The old sequential loop made a 40-unit run take minutes during which the
  /// UI had nothing to show; four in flight cuts the wait roughly fourfold
  /// while keeping the proxy and the provider quota comfortable.
  static const int reviewConcurrency = 4;

  /// Attempts per requirement before it is recorded as a failure.
  ///
  /// Only errors flagged retryable are re-sent (network, timeout, 5xx). A
  /// flaky connection used to cost a requirement outright and the run moved
  /// on, so a whole document could quietly lose units to a brief blip.
  static const int maxReviewAttempts = 3;

  /// Base delay for retry backoff; doubles on each further attempt.
  static const Duration reviewRetryBaseDelay = Duration(milliseconds: 400);
}
