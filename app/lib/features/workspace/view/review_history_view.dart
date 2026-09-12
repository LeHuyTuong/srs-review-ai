/// Review history — saved sessions on this device, newest first. Opening a
/// session restores the full inventory and its findings.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class ReviewHistoryView extends ConsumerStatefulWidget {
  const ReviewHistoryView({super.key});

  @override
  ConsumerState<ReviewHistoryView> createState() => _ReviewHistoryViewState();
}

class _ReviewHistoryViewState extends ConsumerState<ReviewHistoryView> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(
      () => ref.read(workspaceViewModelProvider.notifier).loadHistory(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    // Reserve the floating chrome's height as CONTENT padding so the page
    // starts below the bars but still scrolls behind them (see ChromeInsets).
    final insets = ChromeInsets.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg + insets.top,
        AppSpacing.lg,
        AppSpacing.lg + insets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                kicker: 'Your pre-submission companion',
                title: 'Review history',
                subtitle:
                    'A little progress, every review. Revisit your saved '
                    'sessions.',
              ),
              const SizedBox(height: AppSpacing.xl),
              if (state.error != null) ...[
                WErrorBanner(message: state.error!),
                const SizedBox(height: AppSpacing.md),
              ],
              WPanel(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saved reviews',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.ink,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Offline reviews stay on this device. Each '
                                  'completed run is kept here (up to 30).',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          WButton.secondary(
                            label: 'Refresh',
                            icon: Icons.refresh,
                            onPressed: viewModel.loadHistory,
                          ),
                        ],
                      ),
                    ),
                    if (state.historyLoading)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (state.history.isEmpty)
                      WEmptyState(
                        icon: Icons.history,
                        title: 'Your review journey starts here',
                        message:
                            'Run your first review from the Document review '
                            'view — it will be saved here automatically.',
                      )
                    else
                      for (final session in state.history)
                        _HistoryRow(
                          session: session,
                          onOpen: () async {
                            final opened = await viewModel.openSession(
                              session.id,
                            );
                            if (opened && context.mounted) {
                              // Jump to the findings the session contains.
                              context.go('/workspace');
                            }
                          },
                          onDelete: () => viewModel.deleteSession(session.id),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: () => showSettingsModal(context, ref),
                icon: Icon(Icons.settings_outlined, size: 16, color: colors.muted),
                label: Text(
                  'Review settings',
                  style: TextStyle(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  final SavedSession session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  bool get isMock {
    try {
      final payload = jsonDecode(session.payloadJson) as Map<String, dynamic>;
      final result = payload['result'] as Map<String, dynamic>?;
      return result?['mock'] as bool? ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final created = session.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(created.day)}/${two(created.month)}/${created.year} '
        '${two(created.hour)}:${two(created.minute)}';

    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 44,
              decoration: BoxDecoration(
                color: colors.sageBg,
                borderRadius: AppRadius.boxSm,
              ),
              child: Icon(Icons.description_outlined, color: colors.sage),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$stamp · saved on this device',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            WBadge(
              label: isMock ? 'Mock' : 'Online',
              tint: isMock ? WBadgeTint.green : WBadgeTint.neutral,
            ),
            IconButton(
              tooltip: 'Delete session',
              icon: const Icon(Icons.delete_outline, size: 19),
              color: colors.muted,
              onPressed: onDelete,
            ),
            Icon(Icons.chevron_right, size: 17, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
