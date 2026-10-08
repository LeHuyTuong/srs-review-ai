import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/role/app_role.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_tokens.dart';
import 'core/theme/workspace_colors.dart';
import 'features/auth/view/account_view.dart';
import 'features/auth/view_model/session_view_model.dart';
import 'features/workspace/view/workspace_shortcuts.dart';
import 'review_history/services/session_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dev-only hook (web): opening the app with '?smoke=semantics' in the URL
  // enables Flutter's accessibility DOM, so automated browsers — and screen
  // readers — can see the canvas-rendered UI as real, labelled elements.
  // (A '#fragment' was tried first but breaks go_router's initial matching.)
  if (kIsWeb && Uri.base.queryParameters.containsKey('smoke')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  // Awaited up front so the workspace draft (steps 1–2) is readable from the
  // very first build instead of flickering through an empty first-run card.
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

class SrsReviewApp extends ConsumerStatefulWidget {
  const SrsReviewApp({super.key});

  @override
  ConsumerState<SrsReviewApp> createState() => _SrsReviewAppState();
}

class _SrsReviewAppState extends ConsumerState<SrsReviewApp> {
  /// Built lazily, ONCE PER ROLE.
  ///
  /// ADR-0020 turns the role from a build-time constant into something the
  /// server tells us, so the router can no longer be a `final` field read
  /// before the first request. Rebuilding it every frame would throw away each
  /// shell's scroll and tab state, so the two instances are kept and picked
  /// between — a role is one of two values and the map is the whole cache.
  final Map<AppRole, GoRouter> _routers = {};

  GoRouter _routerFor(AppRole role) => _routers.putIfAbsent(
    role,
    () => buildRouter(scope: AppRoleScope(role: role)),
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionViewModelProvider);

    // The THREE states below are why this is a gate rather than a redirect:
    //
    // * asking  — a spinner. Showing the form here would flash it on every
    //             cold start of an already-signed-in user.
    // * offline — a message and a retry, NOT the login form. A dead proxy
    //             would otherwise look like "your session expired", and the
    //             login form would fail too, which reads as a wrong password.
    // * signed out — the account surface.
    //
    // Everything is inside MaterialApp so the theme and the localized
    // delegates are the same on every branch; a bare `MaterialApp` per branch
    // would give the login screen a different theme from the app behind it.
    final child = switch (session.status) {
      SessionStatus.asking => const _SessionPending(),
      SessionStatus.offline => _SessionOffline(
        message: session.error,
        onRetry: () => ref.read(sessionViewModelProvider.notifier).restore(),
      ),
      SessionStatus.signedOut => const AccountView(),
      SessionStatus.signedIn => _SignedInApp(
        router: _routerFor(session.identity!.role),
      ),
    };

    return MaterialApp(
      title: 'SRS Review AI',
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: child,
    );
  }
}

/// The shells, mounted under an inner `MaterialApp.router`.
///
/// A `Router` cannot be mounted as a plain child of another `MaterialApp`, so
/// the signed-in branch carries its own — and `builder` is repeated here rather
/// than hoisted, because `WorkspaceShortcuts` must sit above the NAVIGATOR that
/// the dialogs are pushed into. Hoisting it to the outer app would put it above
/// the inner navigator and Esc-to-close would stop working.
class _SignedInApp extends StatelessWidget {
  const _SignedInApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    routerConfig: router,
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

/// Waiting for `/auth/me`. Deliberately not a blank frame: a cold start on a
/// slow link would otherwise look like a frozen app.
class _SessionPending extends StatelessWidget {
  const _SessionPending();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// The server could not be reached while asking who we are.
///
/// This is NOT a sign-out. The cookie is still on disk and may well be valid;
/// showing the login form here would make a wifi blip look like an expired
/// session, and the form would fail for the same reason the check did.
class _SessionOffline extends StatelessWidget {
  const _SessionOffline({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      // Scrollable: the column is taller than a 560px test window (measured:
      // overflowed by 3408px before this was added, because the message wraps
      // to many lines in a narrow viewport). A centred non-scrolling column
      // hides the retry button off-screen on exactly the small devices where
      // the retry matters.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: colors.muted),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Không kết nối được máy chủ',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message ?? 'Kiểm lại proxy rồi thử lại.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      ),
    );
  }
}
