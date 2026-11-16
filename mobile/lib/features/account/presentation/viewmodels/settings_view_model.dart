import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';

/// ViewModel của khu vực demo trong Settings.
/// View chỉ gọi ViewModel; ViewModel mới gọi Service (không chạm Firebase SDK).
class SettingsViewModel {
  SettingsViewModel({
    required this._analytics,
    required this._crashlytics,
    required this._userRoleReader,
  });

  final AnalyticsService _analytics;
  final CrashlyticsService _crashlytics;
  final String Function() _userRoleReader;

  Future<void> runTestCrash() async {
    final role = _userRoleReader();

    // 1. Ghi sự kiện Analytics (#7) và khóa chẩn đoán trước khi crash.
    await _analytics.logTriggerTestCrash(userRole: role);
    await _crashlytics.setCustomKey('user_role', role);
    await _crashlytics.setCustomKey('crash_source', 'settings_test_button');

    // 2. Chờ ngắn để log/key kịp ghi xuống đĩa, rồi mới crash.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _crashlytics.triggerTestCrash();
  }
}

final settingsViewModelProvider = Provider<SettingsViewModel>((ref) {
  return SettingsViewModel(
    analytics: ref.watch(analyticsServiceProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
    userRoleReader: () =>
        ref.read(sessionProvider)?.isSupervisor == true ? 'supervisor' : 'user',
  );
});
