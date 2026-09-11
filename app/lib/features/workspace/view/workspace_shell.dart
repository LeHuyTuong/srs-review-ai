/// Adaptive shell for the workspace: NavigationRail sidebar on wide windows,
/// drawer navigation on phones — the Flutter translation of the brief's
/// fixed sidebar + mobile hamburger pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/content_shell.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class WorkspaceDestination {
  const WorkspaceDestination(this.route, this.label, this.icon);

  final String route;
  final String label;
  final IconData icon;
}

const List<WorkspaceDestination> kWorkspaceDestinations = [
  WorkspaceDestination('/workspace', 'Document review', Icons.description_outlined),
  WorkspaceDestination('/history', 'Review history', Icons.history),
  WorkspaceDestination('/syllabus', 'Syllabus & rubric', Icons.menu_book_outlined),
];

class WorkspaceShell extends ConsumerWidget {
  const WorkspaceShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 1100;
    final mockMode = ref.watch(mockModeProvider);

    // Port of the brief's toast: announcements ("N units reviewed · saved on
    // this device") surface as a transient banner.
    ref.listen(
      workspaceViewModelProvider.select((state) => state.toast),
      (previous, next) {
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
      },
    );

    // Errors must reach the shell too. A run used to be started from a modal
    // that popped itself immediately, so any error it produced was written
    // into a widget tree that no longer existed — the user saw nothing at all.
    ref.listen(
      workspaceViewModelProvider.select((state) => state.error),
      (previous, next) {
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
      },
    );

    final body = Row(
      children: [
        if (isWide) _Sidebar(navigationShell: navigationShell),
        Expanded(
          child: Column(
            children: [
              _TopBar(
                navigationShell: navigationShell,
                showMenuButton: !isWide,
                mockMode: mockMode,
              ),
              // The review progress surface lives in the SHELL, not in the
              // modal that starts the run. Previously the run button popped
              // the sheet that owned the only progress UI, so a multi-minute
              // review was byte-for-byte indistinguishable from a frozen
              // screen. See docs/uiux/audit-2026-09-11.md (P0-1, P0-2).
              const ReviewProgressBar(),
              Expanded(child: navigationShell),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      drawer: isWide ? null : _AppDrawer(navigationShell: navigationShell),
      body: body,
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

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          if (showMenuButton)
            Builder(
              builder: (drawerContext) => IconButton(
                tooltip: 'Open navigation',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(drawerContext).openDrawer(),
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Workspace',
                    style: TextStyle(color: colors.muted),
                  ),
                  TextSpan(text: '  /  ', style: TextStyle(color: colors.muted)),
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
          Icon(
            mockMode ? Icons.cloud_off_outlined : Icons.cloud_outlined,
            size: 16,
            color: colors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            mockMode ? 'Offline mock' : 'Online',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            tooltip: 'Help & getting started',
            icon: const Icon(Icons.help_outline),
            color: colors.muted,
            onPressed: () => showHelpModal(context, ref),
          ),
        ],
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
    if (!state.isRunning) return const SizedBox.shrink();

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
      eta = '~${formatElapsed(Duration(milliseconds: (per * remaining).round()))} left';
    }

    return Semantics(
      liveRegion: true,
      label: 'Review in progress',
      child: Container(
        key: const Key('review-progress-bar'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.sageBg,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Column(
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
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colors.muted),
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

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Container(
      width: 228,
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
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: colors.brand, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'SRS Review',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                WBadge(label: 'AI', tint: WBadgeTint.green),
              ],
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
              '',
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final WorkspaceDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
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
          InkWell(
            onTap: () => showSettingsModal(context, ref),
            borderRadius: AppRadius.boxSm,
            child: Row(
              children: [
                Text(
                  'Explore mock mode',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.arrow_forward, size: 14, color: colors.brand),
              ],
            ),
          ),
        ],
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
                '',
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
                '',
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

/// Content column shared by every workspace view: readable width on desktop,
/// full-bleed on phones.
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ContentShell(
      maxWidth: 1100,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}
