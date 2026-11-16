import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';

// Hồi quy: địa chỉ server KHÔNG được hardcode vào repo. Không cấu hình
// SRS_API_BASE_URL thì trả '' (app lùi về chế độ minh hoạ), không đoán 10.0.2.2
// (chỉ có trong emulator → máy thật timeout "Máy chủ AI không phản hồi").
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test('không cấu hình thì trống trên $platform', () {
      debugDefaultTargetPlatformOverride = platform;
      dotenv.loadFromString(isOptional: true);
      expect(resolveBaseUrl(), isEmpty);
    });
  }

  test('đọc SRS_API_BASE_URL từ .env và bỏ dấu / cuối', () {
    dotenv.loadFromString(envString: 'SRS_API_BASE_URL=http://example.test:8000/');
    expect(resolveBaseUrl(), 'http://example.test:8000');
  });
}
