import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/session_database.dart';
import 'features/workspace/view/workspace_shortcuts.dart';

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
  // History lives in a database (one record per session, no whole-list
  // rewrite, no localStorage ceiling). Chosen here, once, so every reader goes
  // through the same store — and so a platform without a database location
  // keeps the old store instead of losing the history.
  final sessionStore = await openSessionStore(prefs: prefs);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionStoreProvider.overrideWithValue(sessionStore),
      ],
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
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    routerConfig: _router,
    // `builder` runs ABOVE the Navigator, which is the whole point: a
    // `Shortcuts` widget installed here is an ancestor of every route,
    // including the ones `showDialog` pushes. A dialog is a sibling of the
    // shell inside the root Overlay, so a shortcut layer inside the shell can
    // never see a key pressed while a modal is open — and Esc-to-close is the
    // least negotiable desktop shortcut there is.
    builder: (context, child) =>
        WorkspaceShortcuts(child: child ?? const SizedBox.shrink()),
  );
}
