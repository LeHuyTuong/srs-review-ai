import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/app/app_web.dart';
import 'package:srs_review_ai_admin_web/firebase_options.dart';

/// Entrypoint của Admin Web — chạy độc lập với Mobile App.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crashlytics không hỗ trợ web nên không đăng ký crash handler ở đây.
  runApp(const ProviderScope(child: SrsReviewAiWebApp()));
}
