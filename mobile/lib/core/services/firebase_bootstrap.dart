import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:srs_review_ai_mobile/core/services/crashlytics_support.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';

// Chạy trong isolate riêng khi app ở nền hoặc đã tắt, nên phải khởi tạo Firebase lại tại đây.
// Handler này chỉ chạy trên native, nên cấu hình lấy từ google-services.json do
// Gradle plugin sinh ra; không phụ thuộc dart-define.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// Điểm khởi tạo duy nhất của Firebase để main() không phải biết từng SDK.
Future<void> bootstrapFirebase({
  Future<void> Function()? initializeFirebase,
  FirebaseCrashlytics Function()? crashlyticsFactory,
  VoidCallback? registerBackgroundMessaging,
  bool forceCrashReporting = _forceCrashReporting,
}) async {
  // Các seam cho test không gọi SDK native hoặc Firebase thật.
  if (initializeFirebase != null) {
    await initializeFirebase();
  } else if (kIsWeb) {
    // Web không có cấu hình native: client key đến từ define hoặc từ
    // web/firebase-config.js lúc chạy.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else {
    // Native lấy cấu hình từ google-services.json (Gradle plugin), nên app khởi
    // động được bằng "flutter run" trần mà không cần dart-define.
    await Firebase.initializeApp();
  }

  if (supportsCrashlytics) {
    final crashlytics =
        (crashlyticsFactory ?? () => FirebaseCrashlytics.instance)();
    // Bản debug chỉ gửi báo cáo khi được bật rõ ràng.
    await crashlytics.setCrashlyticsCollectionEnabled(
      !kDebugMode || forceCrashReporting,
    );
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    // Lỗi bất đồng bộ ngoài khung Flutter không đi qua FlutterError.onError.
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  if (!kIsWeb) {
    if (registerBackgroundMessaging != null) {
      registerBackgroundMessaging();
    } else {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
    }
  }
}

// Bật bằng --dart-define=CRASH_REPORTING=true khi cần quay bằng chứng Crashlytics từ bản debug.
const bool _forceCrashReporting = bool.fromEnvironment('CRASH_REPORTING');
