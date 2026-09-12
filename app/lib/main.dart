import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dev-only hook (web): opening the app with '?smoke=semantics' in the URL
  // enables Flutter's accessibility DOM, so automated browsers — and screen
  // readers — can see the canvas-rendered UI as real, labelled elements.
  // (A '#fragment' was tried first but breaks go_router's initial matching.)
  if (kIsWeb && Uri.base.queryParameters.containsKey('smoke')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  // Awaited up front so the workspace can restore its persisted snapshot from
  // the very first build instead of flickering through an empty state.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const SrsReviewApp(),
    ),
  );
}

class SrsReviewApp extends StatefulWidget {
  const SrsReviewApp({super.key});

  @override
  State<SrsReviewApp> createState() => _SrsReviewAppState();
}

class _SrsReviewAppState extends State<SrsReviewApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SRS Review AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );
}
