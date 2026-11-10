import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';

// Hồi quy: không cấu hình SRS_API_BASE_URL thì Android từng gọi 10.0.2.2
// (chỉ có trong emulator) → máy thật timeout "Máy chủ AI không phản hồi".
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test('mặc định trỏ về server đã deploy trên $platform', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(resolveBaseUrl(), deployedBaseUrl);
      expect(resolveBaseUrl(), isNot(contains('10.0.2.2')));
    });
  }
}
