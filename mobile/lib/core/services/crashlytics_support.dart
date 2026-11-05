import 'package:flutter/foundation.dart';

// Kiểm tra web trước: trình duyệt có thể báo nền tảng Android hoặc macOS.
bool get supportsCrashlytics =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
