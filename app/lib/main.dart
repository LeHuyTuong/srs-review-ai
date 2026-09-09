import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: SrsReviewApp()));
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
