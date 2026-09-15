/// Document review — the workspace's main view: workflow, document card,
/// metric cards, the Inventory/Findings/Syllabus tabs and the readiness
/// panel. Ported from the brief's main column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_breakpoint.dart';
import '../../../core/layout/app_viewport.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../models/workspace_tab.dart';
import '../view_model/workspace_tab_controller.dart';
import '../view_model/workspace_view_model.dart';
import 'findings_tab.dart';
import 'inventory_tab.dart';
import 'readiness_panel.dart';
import 'syllabus_tab.dart';
import 'workspace_modals.dart';
import 'workspace_shell.dart';
import 'workspace_widgets.dart';

int _workflowStepFor(WorkspaceTab tab) => switch (tab) {
  WorkspaceTab.inventory => 2,
  WorkspaceTab.findings => 3,
  WorkspaceTab.syllabus => 3,
};

class DocumentReviewView extends ConsumerWidget {
  const DocumentReviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final tab = ref.watch(workspaceTabProvider);
    final colors = context.workspaceColors;
    // Read from the shell's viewport rather than from MediaQuery: the layout
    // decision for this column is not "how wide is the window" but "has the
    // shell already put the readiness panel in its own rail". Re-deriving it
    // here would be a second, divergent copy of the breakpoint rule.
    final viewport = AppViewport.of(context);
    final showInnerSplit = viewport.showInnerSplit;

    if (state.restoring) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasDocument) {
      return WorkspacePage(
        child: Column(
          children: [
            const PageHeading(
              kicker: 'Your pre-submission companion',
              title: 'Document review',
              subtitle: 'A clearer SRS. A more confident submission.',
            ),
            const SizedBox(height: AppSpacing.xxl),
            // While a file is being read/parsed, replace the empty-state card
            // with live progress so large imports don't look frozen.
            if (state.importStatus != null)
              WPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        state.importStatus!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else
              WEmptyState(
                icon: Icons.description_outlined,
                title: 'A second look, backed by evidence.',
                message:
                    'Import your SRS to build the inventory, or explore with '
                    'the synthetic sample — no file needed.',
                action: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    WButton.primary(
                      label: 'Import document',
                      icon: Icons.add,
                      onPressed: () => showImportModal(context, ref),
                    ),
                    WButton.secondary(
                      label: 'Load the sample document',
                      icon: Icons.play_arrow,
                      onPressed: () => ref
                          .read(workspaceViewModelProvider.notifier)
                          .loadDemo(),
                    ),
                  ],
                ),
              ),
            // Import errors surface AFTER the modal has popped (e.g. the
            // 25 MB size cap), so the empty state itself must carry them —
            // otherwise the rejection is invisible.
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              WErrorBanner(message: state.error!),
            ],
          ],
        ),
      );
    }

    return WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            kicker: 'Your pre-submission companion',
            title: 'Document review',
            subtitle: 'A clearer SRS. A more confident submission.',
            actions: [
              WButton.secondary(
                label: 'Export report',
                icon: Icons.download_outlined,
                onPressed: () => showExportModal(context, ref),
              ),
              WButton.primary(
                label: 'Import document',
                icon: Icons.add,
                onPressed: () => showImportModal(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkflowSteps(
            currentStep: _workflowStepFor(tab),
            onStepTap: (step) {
              switch (step) {
                case 1:
                  showImportModal(context, ref);
                case 2:
                  ref
                      .read(workspaceTabProvider.notifier)
                      .select(WorkspaceTab.inventory);
                case 3:
                  if (state.hasResult) {
                    ref
                        .read(workspaceTabProvider.notifier)
                        .select(WorkspaceTab.findings);
                  } else {
                    showReviewModal(context, ref);
                  }
                case 4:
                  showExportModal(context, ref);
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          _DocumentCard(
            fileName: state.fileName,
            pageCount: state.pageCount,
            sizeLabel: state.sizeLabel,
            isDemo: state.isDemo,
            onInfo: () => showDocumentInfoModal(context, ref),
            onReplace: () => showImportModal(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.lg;
              final columns = constraints.maxWidth >= AppBreakpoints.compactMaxWidth
                  ? 4
                  : 2;
              final metricWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              Widget metric(
                String label,
                int value,
                String note,
                IconData icon,
                Color color,
                Color bg,
              ) => SizedBox(
                width: metricWidth,
                child: MetricCard(
                  label: label,
                  value: value,
                  note: note,
                  icon: icon,
                  color: color,
                  background: bg,
                  onTap: () => ref
                      .read(workspaceTabProvider.notifier)
                      .select(WorkspaceTab.inventory),
                ),
              );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  metric(
                    'Total units',
                    state.units.length,
                    'Extracted from your document',
                    Icons.layers_outlined,
                    colors.sage,
                    colors.sageBg,
                  ),
                  metric(
                    'Use cases',
                    state.useCaseCount,
                    'Whole use-case context preserved',
                    Icons.description_outlined,
                    colors.blue,
                    colors.blueBg,
                  ),
                  metric(
                    'Other requirements',
                    state.otherRequirementsCount,
                    'Business rules · Non-functional · Functional',
                    Icons.menu_book_outlined,
                    colors.purple,
                    colors.purpleBg,
                  ),
                  metric(
                    'Needs attention',
                    state.attentionCount,
                    'Malformed IDs · nothing discarded',
                    Icons.warning_amber_outlined,
                    colors.amber,
                    colors.amberBg,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Flex(
            direction: showInnerSplit ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: showInnerSplit ? 1 : 0,
                fit: FlexFit.loose,
                child: _TabbedPanel(
                  tab: tab,
                  onTabChanged: (next) =>
                      ref.read(workspaceTabProvider.notifier).select(next),
                ),
              ),
              // When the shell has taken the panel into its 360px rail, it is
              // omitted here entirely — otherwise the readiness numbers would
              // be on screen twice, once in each column. When it is not in the
              // rail it renders exactly as it did before: side-by-side above
              // 1100, stacked below.
              if (!viewport.showRightRail) ...[
                if (showInnerSplit)
                  const SizedBox(width: AppSpacing.lg)
                else
                  const SizedBox(height: AppSpacing.lg),
                Flexible(
                  flex: 0,
                  fit: FlexFit.loose,
                  child: SizedBox(
                    width: showInnerSplit ? 300 : double.infinity,
                    child: const ReadinessPanel(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.fileName,
    required this.pageCount,
    required this.sizeLabel,
    required this.isDemo,
    required this.onInfo,
    required this.onReplace,
  });

  final String fileName;
  final int pageCount;
  final String sizeLabel;
  final bool isDemo;
  final VoidCallback onInfo;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'DOC';
    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final tile = Container(
            width: 45,
            height: 52,
            decoration: BoxDecoration(
              color: colors.amberBg,
              borderRadius: AppRadius.boxSm,
              border: Border.all(color: colors.amberBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, color: colors.amber, size: 24),
                Text(
                  extension,
                  maxLines: 1,
                  // 0.9 left ~0.4px of slack per character at the old 8px; at
                  // the AppType.micro floor the trailing letter-space pushed a
                  // 4-glyph extension past the 43px tile and it wrapped.
                  // maxLines + the tighter tracking keep the tile one line at
                  // any font the platform resolves.
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                    fontSize: AppType.micro,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          );
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  if (isDemo) ...[
                    const SizedBox(width: AppSpacing.sm),
                    WBadge(label: 'Sample document'),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Software Requirements Specification · Report 3',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$pageCount pages · $sizeLabel · Extraction complete',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                  fontSize: AppType.micro,
                ),
              ),
            ],
          );
          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WBadge(
                label: 'Ready for review',
                tint: WBadgeTint.green,
                leading: Icon(Icons.circle, size: 4, color: colors.sage),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 44x44: the platform minimum tap target. These were 34x34,
                  // measured in the phone-viewport audit
                  // (docs/uiux/audit-2026-09-11.md P1-1).
                  IconButton(
                    tooltip: 'Document information',
                    icon: const Icon(Icons.more_horiz),
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: colors.muted,
                    onPressed: onInfo,
                  ),
                  IconButton(
                    tooltip: 'Replace document',
                    icon: const Icon(Icons.swap_horiz),
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: colors.muted,
                    onPressed: onReplace,
                  ),
                ],
              ),
            ],
          );
          // Phones stack the file header above its actions; wide screens keep
          // the brief's single-row card.
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    tile,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: heading),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: actions),
              ],
            );
          }
          return Row(
            children: [
              tile,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.sm),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _TabbedPanel extends ConsumerWidget {
  const _TabbedPanel({required this.tab, required this.onTabChanged});

  final WorkspaceTab tab;
  final ValueChanged<WorkspaceTab> onTabChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return WPanel(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in const [
                          (WorkspaceTab.inventory, 'Inventory'),
                          (WorkspaceTab.findings, 'Findings'),
                          (WorkspaceTab.syllabus, 'Syllabus checks'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.lg,
                            ),
                            child: InkWell(
                              onTap: () => onTabChanged(entry.$1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md + 1,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: tab == entry.$1
                                          ? colors.brand
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      entry.$2,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: tab == entry.$1
                                                ? colors.brand
                                                : colors.muted,
                                            fontWeight: tab == entry.$1
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tab == entry.$1
                                            ? colors.sageBg
                                            : colors.canvas,
                                        borderRadius: AppRadius.boxSm,
                                      ),
                                      child: Text(
                                        '${switch (entry.$1) {
                                          WorkspaceTab.inventory => state.units.length,
                                          WorkspaceTab.findings => state.result?.findings.length ?? 0,
                                          WorkspaceTab.syllabus => 3,
                                        }}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.muted,
                                              fontSize: AppType.micro,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Ask document',
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  color: colors.muted,
                  onPressed: () => showAskModal(context, ref),
                ),
              ],
            ),
          ),
          switch (tab) {
            WorkspaceTab.inventory => const InventoryTab(),
            WorkspaceTab.findings => const FindingsTab(),
            WorkspaceTab.syllabus => const SyllabusTab(),
          },
        ],
      ),
    );
  }
}
