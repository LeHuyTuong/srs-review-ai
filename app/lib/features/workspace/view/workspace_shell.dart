/// Adaptive shell for the workspace: NavigationRail sidebar on wide windows,
/// drawer navigation on phones — the Flutter translation of the brief's
/// fixed sidebar + mobile hamburger pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_config.dart';
import '../../../core/layout/app_breakpoint.dart';
import '../../../core/layout/app_viewport.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../../../core/widgets/content_shell.dart';
import '../../../core/widgets/glass_surface.dart';
import '../models/workspace_tab.dart';
import '../view_model/workspace_shortcut_commands.dart';
import '../view_model/workspace_tab_controller.dart';
import '../view_model/workspace_view_model.dart';
import 'readiness_panel.dart';
import 'shortcuts_modal.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class WorkspaceDestination {
  const WorkspaceDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Index-aligned with the branches of the [StatefulShellRoute] in
/// `core/router/app_router.dart`: the shell navigates with
/// `navigationShell.goBranch(i)`, so a destination's POSITION here — not a
/// path — is what selects it.
///
/// A `route` field used to live here. It was never read, and it held
/// `/workspace` while the actual route is `/` — wrong data is worse than none.
const List<WorkspaceDestination> kWorkspaceDestinations = [
  WorkspaceDestination('Document review', Icons.description_outlined),
  WorkspaceDestination('Review history', Icons.history),
  WorkspaceDestination('Syllabus & rubric', Icons.menu_book_outlined),
];

/// Height of the floating top bar. Named because the scrolling views have to
/// reserve exactly this much as content padding — see [ChromeInsets].
const double _kTopBarHeight = 58;

/// Vertical space the floating tab bar occupies, including its own margins.
/// Kept in sync with [_GlassTabBar]'s padding so content never rests under it.
const double _kTabBarReserve = 72;

class WorkspaceShell extends ConsumerWidget {
  const WorkspaceShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final mockMode = ref.watch(mockModeProvider);
    // Only `hasDocument` is watched, not the whole view model: the shell must
    // not rebuild on every progress tick of a run, and the shortcut closures
    // below read the live state at the moment they are invoked.
    final hasDocument = ref.watch(
      workspaceViewModelProvider.select((state) => state.hasDocument),
    );
    final viewport = AppViewportData.resolve(
      width: width,
      isDesktop: AppPlatform.isDesktop,
      // The rail carries the readiness panel, which only means something on the
      // review destination with a document loaded. History and Syllabus would
      // show 360px of empty gutter.
      hasRightRailContent: hasDocument && navigationShell.currentIndex == 0,
    );

    _registerShortcutCommands(ref, context);

    // Port of the brief's toast: announcements ("N units reviewed · saved on
    // this device") surface as a transient banner.
    ref.listen(workspaceViewModelProvider.select((state) => state.toast), (
      previous,
      next,
    ) {
      if (next.isEmpty) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });

    // Errors must reach the shell too. A run used to be started from a modal
    // that popped itself immediately, so any error it produced was written
    // into a widget tree that no longer existed — the user saw nothing at all.
    ref.listen(workspaceViewModelProvider.select((state) => state.error), (
      previous,
      next,
    ) {
      if (next == null || next.isEmpty) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });

    // The chrome FLOATS OVER the content, which is what makes the glass glass.
    //
    // A translucent bar only reads as translucent when something passes behind
    // it. The shell used to be a Column — bar, then scroll view, then tab bar —
    // so the scroll viewport was clipped between the bars and nothing ever
    // crossed them. The backdrop blur then sampled a flat page background, and
    // measurement confirmed the material was cosmetic: the pixel band under the
    // top bar was byte-identical before and after scrolling ((235,237,235)).
    //
    // Now the content owns the full box (Positioned.fill) and the bars are
    // painted on top of it, so scrolling genuinely moves content under them.
    // The bars no longer steal height from the viewport, so each scrolling view
    // reserves the same space as CONTENT padding instead — via [ChromeInsets],
    // read inside the scrollable. Reserving it there rather than with a Padding
    // around the viewport is the whole point: only the resting position moves,
    // so content still scrolls up and under the bar.
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final chromeInsets = EdgeInsets.only(
      top: _kTopBarHeight,
      bottom: viewport.showRail ? 0 : _kTabBarReserve + safeBottom,
    );

    final body = Row(
      children: [
        if (viewport.showRail) _Sidebar(navigationShell: navigationShell),
        Expanded(
          child: Stack(
            children: [
              // The branch content is a nested Navigator, and every route it
              // hosts installs a route-scoped semantics node whose modal
              // barrier marks itself as "blocking the semantics of previously
              // painted nodes" (see `BlockSemantics`). That flag climbs the
              // render tree until it meets a semantic boundary —
              // `RenderObject.isBlockingPreviousSibling` returns false there —
              // so it climbed all the way to the body's Row and wiped out
              // every sibling painted before the content: the whole sidebar.
              //
              // That is why a screen reader could not reach any destination:
              // on web with `?smoke=semantics` the left column produced no
              // `<flt-semantics>` node at all, and the same tree comes out of
              // a widget test. Verified by removing `navigationShell` — the
              // sidebar's labels reappeared in the tree the moment it was
              // replaced by a plain `Text`.
              //
              // Making the branch content a boundary stops the climb here.
              // `explicitChildNodes` then keeps every button and label inside
              // the branch as its own node instead of merging them into this
              // one.
              Positioned.fill(
                // Hand the content only the width left once the rail has taken
                // its slice. Insetting the CONTENT rather than shrinking the
                // stack is what keeps the top bar spanning the whole window.
                right: viewport.showRightRail
                    ? AppBreakpoints.rightRailWidth
                    : 0,
                child: ChromeInsets(
                  insets: chromeInsets,
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: navigationShell,
                  ),
                ),
              ),
              if (viewport.showRightRail) const _WorkspaceRightRail(),
              // The review progress surface lives in the SHELL, not in the
              // modal that starts the run. Previously the run button popped
              // the sheet that owned the only progress UI, so a multi-minute
              // review was byte-for-byte indistinguishable from a frozen
              // screen. See docs/uiux/audit-2026-09-11.md (P0-1, P0-2).
              //
              // It rides in the floating chrome, so it blurs the content behind
              // it for free. It is not reserved as an inset: it only exists
              // while a run is in flight, it covers the top of a page the user
              // is not reading during the run, and reserving it would mean
              // measuring a bar whose cap message wraps to a variable number of
              // lines. Overlaying is also what iOS does with a transient
              // progress banner.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TopBar(
                      navigationShell: navigationShell,
                      showMenuButton: !viewport.showRail,
                      mockMode: mockMode,
                    ),
                    const ReviewProgressBar(),
                  ],
                ),
              ),
              // Narrow screens get a real tab bar instead of only a hamburger.
              // The user's complaint was literally "phải bấm menu chưa ổn lắm"
              // — 3 destinations were two taps away behind a drawer.
              if (viewport.showFloatingTabBar)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _GlassTabBar(navigationShell: navigationShell),
                ),
            ],
          ),
        ),
      ],
    );

    // Android back, mobile-only rule: from History or Syllabus, one press
    // returns to Document review instead of leaving the app. Without this the
    // shell is the only route, so the back button quit the app from any tab —
    // the behaviour every Android user reads as a crash. Scoped to the phone
    // bucket on purpose: on desktop the Esc layer owns dismissal, and on web
    // the browser's own history stack IS the back gesture — intercepting there
    // would desync the URL from the visible branch. A modal or sheet is its
    // own route on top of this one, so back still pops the open dialog first;
    // this only fires when nothing is layered over the shell.
    final backReturnsHome =
        AppPlatform.formFactor == AppFormFactor.phone &&
        navigationShell.currentIndex != 0;

    return PopScope(
      // Keyed: the framework owns PopScopes of its own around routes, and a
      // test that grabbed `find.byType(PopScope).first` read one of those.
      key: const ValueKey('shell-back-guard'),
      canPop: !backReturnsHome,
      onPopInvokedWithResult: (didPop, _) {
        // `goBranch(0)` rather than `context.go('/')`: switching branch
        // preserves each destination's state, exactly like tapping the rail
        // or the floating tab bar does.
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        drawer: viewport.showRail
            ? null
            : _AppDrawer(navigationShell: navigationShell),
        body: AppViewport(data: viewport, child: body),
      ),
    );
  }

  /// Fills the shortcut command slots for this build.
  ///
  /// Every slot is re-assigned on each build, which sounds wasteful but is the
  /// point: the closures capture `navigationShell`, the current branch index and
  /// a `BuildContext` that is valid for `show*Modal`, and all three go stale.
  /// Registering them again is how they stay correct.
  ///
  /// The slots themselves are nullable; a null slot means "this shortcut is
  /// inert", which is what any widget test that never builds the shell gets.
  void _registerShortcutCommands(WidgetRef ref, BuildContext context) {
    final commands = ref.read(workspaceShortcutCommandsProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);

    commands.openImport = () {
      // Starting an import mid-run would race the run for the same document
      // slot, so the key is simply inert while one is in flight.
      if (ref.read(workspaceViewModelProvider).isRunning) return;
      showImportModal(context, ref);
    };
    commands.startOrCancelReview = () {
      final state = ref.read(workspaceViewModelProvider);
      if (state.isRunning) {
        viewModel.cancelReview();
        return;
      }
      if (state.hasDocument) showReviewModal(context, ref);
    };
    commands.exportReport = () {
      if (!ref.read(workspaceViewModelProvider).hasResult) return;
      showExportModal(context, ref);
    };
    commands.openSettings = () => showSettingsModal(context, ref);
    commands.goDestination = (index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
    commands.goSubTab = (tab) {
      if (navigationShell.currentIndex != 0) {
        navigationShell.goBranch(0);
      }
      ref.read(workspaceTabProvider.notifier).select(tab);
    };
    commands.showShortcuts = () => showShortcutsModal(context, ref);
    commands.dismiss = () {
      final state = ref.read(workspaceViewModelProvider);
      if (state.isRunning) {
        // Esc during a run cancels the run; it must not pop the page out from
        // under a run that is still writing results.
        viewModel.cancelReview();
        return;
      }
      final navigator = Navigator.of(context);
      // One route per press. Exactly one Esc handler must run: the app-level
      // Shortcuts resolves to AppDismissIntent, and because it sits nearer to
      // the focus than the framework's root Escape->DismissIntent binding, that
      // binding never fires — see AppDismissIntent in workspace_shortcuts.dart.
      if (navigator.canPop()) navigator.pop();
    };
  }
}

/// The 360px readiness column, shown only at `ultra`/`cinema` on the review
/// destination.
///
/// It starts BELOW the top bar (`top: _kTopBarHeight`) so the bar spans the
/// full window instead of stopping at the rail. The review progress bar is a
/// transient overlay that will cross the top of this column during a run —
/// accepted, because it is semi-transparent and already overlays content the
/// same way.
class _WorkspaceRightRail extends StatelessWidget {
  const _WorkspaceRightRail();

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return Positioned(
      top: _kTopBarHeight,
      right: 0,
      bottom: 0,
      width: AppBreakpoints.rightRailWidth,
      child: Container(
        key: const Key('right-rail'),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(left: BorderSide(color: colors.border)),
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ReadinessPanel(),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.navigationShell,
    required this.showMenuButton,
    required this.mockMode,
  });
  final StatefulNavigationShell navigationShell;
  final bool showMenuButton;
  final bool mockMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final current = kWorkspaceDestinations[navigationShell.currentIndex];
    final connectionStatus = _connectionStatusFor(
      colors: colors,
      mockMode: mockMode,
      status: ref.watch(proxyStatusProvider),
    );

    // Glass on the top bar: in iOS 26 the navigation bar IS the material —
    // content scrolls under it and stays faintly visible through it. Radius 0
    // so it sits flush against the window edge, like the system bar.
    return SizedBox(
      height: _kTopBarHeight,
      child: GlassSurface(
        radius: 0,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            if (showMenuButton)
              // No `Semantics` wrapper here. `IconButton(tooltip:)` already names
              // the button and gives it `role=button` — verified as one node,
              // labelled, on the help button below. Wrapping it in an explicit
              // labelled Semantics produced TWO button nodes with the same name
              // (the wrapper's `label` and the IconButton's own `tooltip`), so a
              // screen reader announced "Open navigation" twice. Same class of
              // duplication as the tab items, which needed the opposite fix
              // because they had no built-in label to begin with.
              Builder(
                builder: (drawerContext) => IconButton(
                  tooltip: 'Open navigation',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                ),
              ),
            Expanded(
              // The breadcrumb is announced once, as a single header, instead of
              // as three fragments ("Workspace", "/", "Document review") that a
              // screen reader has to reassemble.
              //
              // This publishes correctly now that the chrome floats over the
              // content: it reaches the tree as an <h2> "Workspace / Document
              // review". It used to be missing entirely, which six rounds of this
              // audit attributed to shell/route composition — see the correction
              // in docs/uiux/audit-2026-09-11.md §10.
              child: Semantics(
                header: true,
                label: 'Workspace / ${current.label}',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Workspace',
                        style: TextStyle(color: colors.muted),
                      ),
                      TextSpan(
                        text: '  /  ',
                        style: TextStyle(color: colors.muted),
                      ),
                      TextSpan(
                        text: current.label,
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            AppInkWell(
              // Rechecking is the natural next gesture when the pill says the
              // proxy is gone: the user fixes the proxy, taps, and it updates
              // without an app restart.
              onTap: () => ref.invalidate(proxyStatusProvider),
              borderRadius: AppRadius.boxSm,
              child: Semantics(
                button: true,
                label:
                    'Connection status: ${connectionStatus.label}. Double tap to recheck.',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        connectionStatus.icon,
                        size: 16,
                        color: connectionStatus.color,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        connectionStatus.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: connectionStatus.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Desktop-only, and a NEW node rather than an edit of the Help
            // button's tooltip: `workspace_shell_test.dart` asserts
            // 'Help & getting started' appears on exactly one semantics node,
            // so appending a shortcut hint to it would break that count.
            if (AppPlatform.isDesktop)
              IconButton(
                tooltip: 'Keyboard shortcuts',
                icon: const Icon(Icons.keyboard_command_key),
                color: colors.muted,
                onPressed: () => showShortcutsModal(context, ref),
              ),
            IconButton(
              tooltip: 'Help & getting started',
              icon: const Icon(Icons.help_outline),
              color: colors.muted,
              onPressed: () => showHelpModal(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent review progress, pinned under the top bar and owned by the
/// shell so it survives the modal that started the run.
///
/// Shows the stage label, a determinate bar, live elapsed time, the cap
/// warning when the per-run limit bites, and a Cancel button bound to
/// [WorkspaceViewModel.cancelReview]. Renders nothing when idle.
class ReviewProgressBar extends ConsumerWidget {
  const ReviewProgressBar({super.key});

  static String formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    if (!state.isRunning) return _RunSummaryBar(state: state);

    final progress = state.progress!;
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final elapsed = state.runElapsed;
    final total = progress.total;
    final remaining = total - progress.completed;

    // A rough ETA: only honest once at least one unit has finished.
    String? eta;
    if (elapsed != null && progress.completed > 0 && remaining > 0) {
      final per = elapsed.inMilliseconds / progress.completed;
      eta =
          '~${formatElapsed(Duration(milliseconds: (per * remaining).round()))} left';
    }

    return Semantics(
      // `container: true` gives the surface its own node so the progress text
      // is reachable as a unit.
      //
      // NOT `explicitChildNodes`: that disowns the subtree below, and the
      // Cancel button inside stopped being focusable (verified with
      // `tester.getSemantics` — Cancel went from one node to none). The
      // remaining accessibility gap here is NOT local to this widget: the whole
      // shell chrome outside `navigationShell` is missing from the semantics
      // tree. Confirmed both in a widget test and in the browser — 'Workspace',
      // 'Online', 'Help & getting started' and this bar are all absent, while
      // 'Review overview' from the branch content is present. See
      // docs/uiux/audit-2026-09-11.md §6c.
      container: true,
      liveRegion: true,
      label: 'Review in progress. ${progress.label}',
      child: GlassSurface(
        key: const Key('review-progress-bar'),
        // Control layer, not content: this is exactly the surface Apple's
        // guidance allows glass on. radius 0 keeps it flush under the top bar.
        compact: true,
        radius: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          // MainAxisSize.min keeps this bar hugging its content. The bar is a
          // non-flex child of the shell's Column and is laid out against
          // unbounded height, so a default (max) Column would try to fill it.
          // (An earlier 390 x 100000px overflow here was NOT this — it was a
          // throwing GlassSurface whose RenderErrorBox takes infinite height.
          // See the note in core/widgets/glass_surface.dart.)
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (elapsed != null)
                  Text(
                    formatElapsed(elapsed),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (eta != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    eta,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ],
                // 48 px tap target: the old progress row had no reachable
                // control at all, and 44 is the platform floor.
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: viewModel.cancelReview,
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(value: progress.fraction),
            if (progress.skipped > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '${progress.skipped} units in this document are outside this '
                  'run — the per-run limit is ${AppConfig.maxRequirementsPerRun}. '
                  'Nothing is dropped from your inventory.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bar that replaces the progress bar the moment a run ends.
///
/// Before this, finishing a run put the user back on exactly the screen they
/// started from: the findings were one tab away with nothing pointing at them,
/// and the only signal was a 4.5-second toast. This surface stays until the
/// user acts on it, and carries the two actions a finished run implies.
class _RunSummaryBar extends ConsumerWidget {
  const _RunSummaryBar({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.showsRunSummary) return const SizedBox.shrink();

    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final findings = state.result?.findings.length ?? 0;
    final failed = state.result?.failed ?? 0;

    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'Review finished. ${state.runReviewed} units reviewed, '
          '$findings findings.',
      child: GlassSurface(
        key: const Key('run-summary-bar'),
        compact: true,
        radius: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: colors.sage),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Review finished · ${state.runReviewed} units reviewed · '
                '$findings findings'
                // A run where units failed must not read as a clean result —
                // the same honesty rule the toast already follows.
                '${failed > 0 ? ' · $failed failed' : ''}'
                '${state.runSkipped > 0 ? ' · ${state.runSkipped} left out by the ${AppConfig.maxRequirementsPerRun}-unit cap' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              // Goes through the shortcut command registry rather than
              // selecting the tab directly: this bar is visible on all three
              // destinations, and `goSubTab` is the one place that knows to
              // switch back to Document review first.
              onPressed: () => ref
                  .read(workspaceShortcutCommandsProvider)
                  .goSubTab
                  ?.call(WorkspaceTab.findings),
              child: const Text('View findings'),
            ),
            IconButton(
              tooltip: 'Export report',
              icon: const Icon(Icons.download_outlined, size: 17),
              color: colors.muted,
              onPressed: () => showExportModal(context, ref),
            ),
            IconButton(
              tooltip: 'Dismiss summary',
              icon: const Icon(Icons.close, size: 17),
              color: colors.muted,
              onPressed: viewModel.dismissRunSummary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Container(
      width: AppBreakpoints.railWidth,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            // Read as one name, not as "SRS Review" + a floating "AI" badge.
            child: Semantics(
              label: 'SRS Review AI',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: colors.brand,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    // The rail is 187px of content at any platform; the word
                    // must ellipsize before the fixed badge can be crowded
                    // out — the 840+ non-desktop rail band exposed exactly
                    // that when a wide-window native build grew a rail.
                    child: Text(
                      'SRS Review',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  WBadge(label: 'AI', tint: WBadgeTint.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'WORKSPACE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < kWorkspaceDestinations.length; i++)
            _NavItem(
              destination: kWorkspaceDestinations[i],
              active: navigationShell.currentIndex == i,
              shortcutHint: _destinationShortcutHint(i),
              onTap: () => navigationShell.goBranch(
                i,
                initialLocation: i == navigationShell.currentIndex,
              ),
            ),
          const Spacer(),
          _OfflineCard(mockMode: ref.watch(mockModeProvider)),
          const SizedBox(height: AppSpacing.lg),
          _NavItem(
            destination: const WorkspaceDestination(
              'Settings',
              Icons.settings_outlined,
            ),
            active: false,
            onTap: () => showSettingsModal(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

// Private sidebar widgets live below; shared badges come from
// workspace_widgets.dart.

/// `⌘1` / `Ctrl+1` — the hint shown next to a destination, desktop only.
///
/// Returns null off desktop, because a `Tooltip` wraps the item in a second
/// semantics node carrying this text, and `workspace_shell_test.dart` asserts
/// each destination label is announced exactly once.
String? _destinationShortcutHint(int index) {
  if (!AppPlatform.isDesktop) return null;
  return AppPlatform.usesCommandKey ? '⌘${index + 1}' : 'Ctrl+${index + 1}';
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
    this.shortcutHint,
  });

  final WorkspaceDestination destination;
  final bool active;
  final VoidCallback onTap;
  final String? shortcutHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    // Same contract as [_GlassTabItem]: one node per destination, named after
    // it, flagged as a button because it is tappable, and carrying `selected`
    // so a screen reader says which destination is on screen.
    //
    // Without it, the icon and the label each publish their own semantics on
    // top of the InkWell's, so the destination is announced twice — and the
    // merged node still never says it is a button.
    final item = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        button: true,
        selected: active,
        label: destination.label,
        // Without this the icon's and label's own semantics are merged on top
        // of ours, so a screen reader announces the item twice.
        excludeSemantics: true,
        child: AppInkWell(
          onTap: onTap,
          borderRadius: AppRadius.boxSm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md - 2,
            ),
            decoration: BoxDecoration(
              color: active ? colors.navActiveBg : Colors.transparent,
              borderRadius: AppRadius.boxSm,
            ),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  size: 19,
                  color: active ? colors.navActiveText : colors.muted,
                ),
                const SizedBox(width: AppSpacing.md - 2),
                Expanded(
                  child: Text(
                    destination.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: active ? colors.navActiveText : colors.muted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (shortcutHint == null) return item;
    // Desktop-only hover affordance: a mouse user discovers ⌘1 here. A touch
    // user never sees it, and a screen reader is unaffected because the
    // tooltip text is a distinct string from the destination label.
    return Tooltip(
      message: '${destination.label} ($shortcutHint)',
      child: item,
    );
  }
}

class _OfflineCard extends ConsumerWidget {
  const _OfflineCard({required this.mockMode});

  final bool mockMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.mint,
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mockMode ? Icons.wifi_off_outlined : Icons.wifi_outlined,
                size: 15,
                color: colors.sage,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Built to work offline',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mockMode ? colors.amber : colors.sage,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your next great submission doesn\'t need a connection.',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A tappable row of text + arrow is invisible to a screen reader as
          // a control: it arrives as two loose labels with no button role.
          Semantics(
            button: true,
            label: 'Explore mock mode',
            excludeSemantics: true,
            child: AppInkWell(
              onTap: () => showSettingsModal(context, ref),
              borderRadius: AppRadius.boxSm,
              child: Row(
                children: [
                  // Expanded, not bare: a bare Text in a Row takes its
                  // intrinsic width and overflows the row on narrow cards
                  // (33px in the 390px phone test — caught by the widget
                  // suite's debug stripes). Expanded lets the label
                  // ellipsize instead, keeping the arrow pinned right.
                  Expanded(
                    child: Text(
                      'Explore mock mode',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.arrow_forward, size: 14, color: colors.brand),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating glass tab bar for narrow screens.
///
/// Before this, every destination on a phone was behind the hamburger: the
/// user's own complaint ("phải bấm menu chưa ổn lắm"). This is the iOS 26
/// bottom bar — a floating, blurred capsule over the content, not a full-width
/// opaque strip.
///
/// Each item is at least 48px tall and the whole bar sits inside the safe
/// area, so it stays reachable and clears the home indicator.
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm + (bottomInset > 0 ? bottomInset * 0.5 : 0),
      ),
      child: GlassSurface(
        key: const Key('glass-tab-bar'),
        compact: true,
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            for (var i = 0; i < kWorkspaceDestinations.length; i++)
              Expanded(
                child: _GlassTabItem(
                  destination: kWorkspaceDestinations[i],
                  active: navigationShell.currentIndex == i,
                  colors: colors,
                  theme: theme,
                  onTap: () => navigationShell.goBranch(
                    i,
                    initialLocation: i == navigationShell.currentIndex,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassTabItem extends StatelessWidget {
  const _GlassTabItem({
    required this.destination,
    required this.active,
    required this.colors,
    required this.theme,
    required this.onTap,
  });

  final WorkspaceDestination destination;
  final bool active;
  final WorkspaceColors colors;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = active ? colors.brand : colors.muted;
    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      // Without this the icon's and label's own semantics are merged on top of
      // ours, so a screen reader announces the tab twice:
      // "Document review Document review" (observed in the browser).
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.boxMd,
        child: Container(
          // 48px, above the 44px platform floor — this bar is the primary
          // navigation on a phone and thumb-accuracy matters here.
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(destination.icon, size: 22, color: colour),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colour,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: colors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'SRS Review AI',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < kWorkspaceDestinations.length; i++)
              _NavItem(
                destination: kWorkspaceDestinations[i],
                active: navigationShell.currentIndex == i,
                onTap: () {
                  Navigator.of(context).pop();
                  navigationShell.goBranch(
                    i,
                    initialLocation: i == navigationShell.currentIndex,
                  );
                },
              ),
            const Divider(),
            _NavItem(
              destination: const WorkspaceDestination(
                'Settings',
                Icons.settings_outlined,
              ),
              active: false,
              onTap: () {
                Navigator.of(context).pop();
                showSettingsModal(context, ref);
              },
            ),
            _NavItem(
              destination: const WorkspaceDestination(
                'Help & getting started',
                Icons.help_outline,
              ),
              active: false,
              onTap: () {
                Navigator.of(context).pop();
                showHelpModal(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// How the connection pill in the top bar should read.
///
/// The old pill read the offline toggle and nothing else, so an app pointed at
/// a dead proxy still advertised "Online" — and a run that came back with zero
/// findings looked like a clean document rather than a broken connection.
/// This asks the proxy and reports what came back, including "I don't know yet".
class _ConnectionStatus {
  const _ConnectionStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;
}

_ConnectionStatus _connectionStatusFor({
  required WorkspaceColors colors,
  required bool mockMode,
  required AsyncValue<bool?> status,
}) {
  if (mockMode) {
    return _ConnectionStatus(
      icon: Icons.cloud_off_outlined,
      label: 'Offline mock',
      color: colors.muted,
    );
  }
  return status.when(
    data: (reachable) => switch (reachable) {
      true => _ConnectionStatus(
        icon: Icons.cloud_outlined,
        label: 'Online',
        color: colors.sage,
      ),
      false => _ConnectionStatus(
        icon: Icons.cloud_off_outlined,
        label: 'Proxy unreachable',
        color: colors.amber,
      ),
      // Mock mode reports null; the toggle already covered it above, so this
      // is only reachable when the mode flips mid-frame.
      null => _ConnectionStatus(
        icon: Icons.cloud_off_outlined,
        label: 'Offline mock',
        color: colors.muted,
      ),
    },
    loading: () => _ConnectionStatus(
      icon: Icons.cloud_queue_outlined,
      label: 'Checking…',
      color: colors.muted,
    ),
    error: (_, _) => _ConnectionStatus(
      icon: Icons.cloud_off_outlined,
      label: 'Proxy unreachable',
      color: colors.amber,
    ),
  );
}

/// Content column shared by every workspace view: readable width on desktop,
/// full-bleed on phones.
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Reserve the floating chrome's height as CONTENT padding, inside the
    // scrollable. This is what lets the page start below the bar while still
    // scrolling up and behind it — an outer Padding would clip it at the bar.
    final insets = ChromeInsets.of(context);
    return ContentShell(
      // From the shell's resolved viewport, not from a literal: below 1440
      // this resolves to 1100 exactly as before, and the wider steps exist
      // only on desktop, so web and mobile cannot be affected.
      maxWidth: AppViewport.of(context).contentMaxWidth,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg + insets.top,
          AppSpacing.lg,
          AppSpacing.lg + insets.bottom,
        ),
        child: child,
      ),
    );
  }
}
