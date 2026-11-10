import 'dart:async';

import 'package:srs_review_ai_mobile/core/domain/relative_time.dart';

/// Chốt đồng hồ "x giờ trước" cho mọi test: 03/10/2026 10:20 là mốc mà 18/18
/// nhãn trong seed `assets/fixtures/academic.json` tính ra đúng như chuỗi cũ,
/// nên ảnh chụp hành vi không trôi theo ngày chạy test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RelativeTime.clock = () => DateTime(2026, 10, 3, 10, 20);
  await testMain();
}
