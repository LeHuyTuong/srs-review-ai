/// Document review — the workspace's main view: workflow, document card,
/// metric cards, the Inventory/Findings/Syllabus tabs and the readiness
/// panel. Ported from the brief's main column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../view_model/workspace_view_model.dart';
import 'findings_tab.dart';
import 'inventory_tab.dart';
import 'source_sheet.dart';
import 'syllabus_tab.dart';
import 'workspace_modals.dart';
import 'workspace_shell.dart';
import 'workspace_widgets.dart';

enum WorkspaceTab { inventory, findings, syllabus }

class DocumentReviewView extends ConsumerStatefulWidget {
  const DocumentReviewView({super.key});

  @override
  ConsumerState<DocumentReviewView> createState() =>
      _DocumentReviewViewState();
}

class _DocumentReviewViewState extends ConsumerState<DocumentReviewView> {
  WorkspaceTab _tab = WorkspaceTab.inventory;

  int get _workflowStep => switch (_tab) {
    WorkspaceTab.inventory => 2,
    WorkspaceTab.findings => 3,
    WorkspaceTab.syllabus => 3,
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final isWide = MediaQuery.sizeOf(context).width >= 1100;

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
            currentStep: _workflowStep,
            onStepTap: (step) {
              switch (step) {
                case 1:
                  showImportModal(context, ref);
                case 2:
                  setState(() => _tab = WorkspaceTab.inventory);
                case 3:
                  if (state.hasResult) {
                    setState(() => _tab = WorkspaceTab.findings);
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
              final columns = constraints.maxWidth >= 700 ? 4 : 2;
              final metricWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              Widget metric(String label, int value, String note, IconData icon,
                      Color color, Color bg) =>
                  SizedBox(
                    width: metricWidth,
                    child: MetricCard(
                      label: label,
                      value: value,
                      note: note,
                      icon: icon,
                      color: color,
                      background: bg,
                      onTap: () => setState(() {
                        _tab = WorkspaceTab.inventory;
                      }),
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
            direction: isWide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: isWide ? 1 : 0,
                fit: FlexFit.loose,
                child: _TabbedPanel(
                  tab: _tab,
                  onTabChanged: (tab) => setState(() => _tab = tab),
                ),
              ),
              if (isWide)
                const SizedBox(width: AppSpacing.lg)
              else
                const SizedBox(height: AppSpacing.lg),
              Flexible(
                flex: 0,
                fit: FlexFit.loose,
                child: SizedBox(
                  width: isWide ? 300 : double.infinity,
                  child: _ReadinessPanel(
                    onInspectFlagged: () =>
                        setState(() => _tab = WorkspaceTab.inventory),
                  ),
                ),
              ),
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
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
                  fontSize: 9.5,
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
                                          WorkspaceTab.inventory =>
                                              state.units.length,
                                          WorkspaceTab.findings =>
                                              state.result?.findings.length ??
                                                  0,
                                          WorkspaceTab.syllabus => 3,
                                        }}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.muted,
                                              fontSize: 8,
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

class _ReadinessPanel extends ConsumerWidget {
  const _ReadinessPanel({required this.onInspectFlagged});

  final VoidCallback onInspectFlagged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final mockMode = ref.watch(mockModeProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final selected = state.selectedCount;
    final total = state.units.length;
    final fraction = total == 0 ? 0.0 : selected / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WPanel(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Review overview',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  WBadge(
                    label: mockMode ? 'Mock mode' : 'Online mode',
                    tint: mockMode ? WBadgeTint.amber : WBadgeTint.green,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A good review starts with a clear inventory.',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$selected',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: colors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' / $total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'units selected',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: AppRadius.boxSm,
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: colors.amberBg,
                  color: colors.sage,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ready to review',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ...[
                ('Whole use-case context', Icons.check_circle_outline),
                ('Source references preserved', Icons.check_circle_outline),
                ('No silent truncation', Icons.check_circle_outline),
              ].map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(row.$2, size: 15, color: colors.sage),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          row.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.attentionCount > 0)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.attentionBg,
                    borderRadius: AppRadius.boxSm,
                    border: Border.all(color: colors.attentionBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: colors.amber,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              '${state.attentionCount} units need a quick look',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.amber,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Unrecognized IDs are kept, not dropped. Check them '
                        'before you review.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.amber,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final unit in state.units.where(
                            (u) => u.malformed,
                          ).take(3))
                            InkWell(
                              onTap: () => showSourceSheet(context, ref, unit),
                              borderRadius: AppRadius.boxSm,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: AppRadius.boxSm,
                                  border: Border.all(color: colors.amberBorder),
                                ),
                                child: Text(
                                  unit.id,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.amber,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      InkWell(
                        onTap: onInspectFlagged,
                        child: Text(
                          'Inspect flagged units →',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.sageBg,
                    borderRadius: AppRadius.boxSm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 17, color: colors.sage),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'All identifiers look good.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.brand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    mockMode ? Icons.wifi_off_outlined : Icons.wifi_outlined,
                    size: 15,
                    color: colors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      mockMode
                          ? 'Offline mock · no API key needed'
                          : 'Proxy review · quotes verified before display',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => showSettingsModal(context, ref),
                    child: Text(
                      'Change',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        WPanel(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(Icons.shield_outlined, size: 28, color: colors.sage),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Evidence, not guesswork.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.brand,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Every finding is checked against your source. No matching '
                'quote? It doesn\'t make the cut.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: () => showHelpModal(context, ref),
                child: Text(
                  'How verification works →',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.sage,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
