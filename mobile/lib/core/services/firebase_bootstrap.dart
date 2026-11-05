import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:srs_review_ai_mobile/firebase_options.dart';

// Chạy trong isolate riêng khi app ở nền hoặc đã tắt, nên phải khởi tạo Firebase lại tại đây.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// Điểm khởi tạo duy nhất của Firebase để main() không phải biết từng SDK.
Future<void> bootstrapFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Bản debug không gửi báo cáo để lỗi đang phát triển không lẫn vào dashboard.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode || _forceCrashReporting,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // Lỗi bất đồng bộ ngoài khung Flutter không đi qua FlutterError.onError.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
}

// Bật bằng --dart-define=CRASH_REPORTING=true khi cần quay bằng chứng Crashlytics từ bản debug.
const bool _forceCrashReporting = bool.fromEnvironment('CRASH_REPORTING');
