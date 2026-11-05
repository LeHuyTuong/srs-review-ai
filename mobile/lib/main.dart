import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/core/services/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase();

  runApp(const ProviderScope(child: SrsReviewApp()));
}
/// Đăng ký 3 "lưới bắt lỗi" cho Crashlytics (Crashlytics không hỗ trợ web).
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // 2. Lỗi bất đồng bộ không được catch (Future, Stream, platform channel).
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // đã xử lý, không để lỗi lan ra ngoài
  };

  // 3. Lỗi phát sinh ngoài isolate chính.
  Isolate.current.addErrorListener(
    RawReceivePort((dynamic pair) async {
      final errorAndStack = pair as List<dynamic>;
      await FirebaseCrashlytics.instance.recordError(
        errorAndStack.first,
        errorAndStack.last as StackTrace?,
        fatal: true,
      );
    }).sendPort,
  );
}
