import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/core/services/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase();

  runApp(const ProviderScope(child: SrsReviewApp()));
}
