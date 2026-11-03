import 'dart:isolate';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _registerCrashHandlers();

  runApp(const ProviderScope(child: SrsReviewApp()));
}

/// Đăng ký 3 "lưới bắt lỗi" cho Crashlytics (Crashlytics không hỗ trợ web).
void _registerCrashHandlers() {
  if (kIsWeb) return;

  // 1. Lỗi framework Flutter (build/layout/paint...) -> ghi nhận là fatal.
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
