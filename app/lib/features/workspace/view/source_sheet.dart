/// Source sheet — the brief's source drawer, rebuilt as a bottom sheet on
/// phones and a side-anchored sheet on wide windows. Shows the unit's
/// metadata, its classification controls and the original source text with
/// copy-to-clipboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../data/models/review_models.dart' show Severity;
import '../models/workspace_findings.dart';
import '../models/workspace_unit.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_widgets.dart';

Future<void> showSourceSheet(
  BuildContext context,
  WidgetRef ref,
  WorkspaceUnit unit, {
  FindingRow? finding,
}) {
  final width = MediaQuery.sizeOf(context).width;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: width >= 700 ? 0.9 : 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (sheetContext, scrollController) => _SourceSheetBody(
        unit: unit,
        finding: finding,
        scrollController: scrollController,
      ),
    ),
  );
}

class _SourceSheetBody extends ConsumerWidget {
  const _SourceSheetBody({
    required this.unit,
    required this.finding,
    required this.scrollController,
  });

  final WorkspaceUnit unit;
  final FindingRow? finding;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    // The sheet may outlive the exact object if the units list is replaced
    // (opening a session); always read the live unit by key.
    final live = ref
        .watch(workspaceViewModelProvider)
        .units
        .where((u) => u.key == unit.key)
        .firstOrNull;
    final current = live ?? unit;
    final activeFinding = finding;

    return WPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 17, color: colors.muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'SOURCE CONTEXT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close source',
                  icon: const Icon(Icons.close),
                  color: colors.muted,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    WBadge(label: current.id),
                    WBadge(
                      label: 'Page ${current.pageIndex + 1}',
                      tint: WBadgeTint.green,
                    ),
                    if (current.malformed)
                      WBadge(label: 'Malformed ID', tint: WBadgeTint.amber),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  current.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  current.section ?? 'Unclassified',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                if (current.malformed) ...[
                  const SizedBox(height: AppSpacing.md),
                  WInfoNote(
                    warning: true,
                    icon: Icons.error_outline,
                    text:
                        'This ID is not in the recognized format. It has been '
                        'preserved as an unknown unit — choose a classification '
                        'to include it in your review.',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: current.kind.label,
                  decoration: InputDecoration(
                    labelText: 'Classification',
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.boxSm,
                    ),
                    isDense: true,
                  ),
                  items: [
                    for (final kind in UnitKind.values)
                      DropdownMenuItem(value: kind.label, child: Text(kind.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    viewModel.classifyUnit(current.key, UnitKind.fromLabel(value));
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // ListTile paints on the nearest Material; wrap it explicitly
                // so the panel's decorated Container doesn't hide the ink.
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    value: current.selected,
                    onChanged: (value) =>
                        viewModel.setUnitSelected(current.key, value ?? false),
                    title: Text(
                      'Include in review',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: colors.brand,
                  ),
                ),
                if (activeFinding != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  WPanel(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            WBadge(
                              label: activeFinding.severity.name,
                              tint: activeFinding.severity == Severity.high
                                  ? WBadgeTint.amber
                                  : WBadgeTint.neutral,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Icon(
                              Icons.shield_outlined,
                              size: 13,
                              color: colors.sage,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Exact match',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.sage,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          activeFinding.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          activeFinding.suggestion,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.muted,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Original source text',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy source text',
                      icon: const Icon(Icons.copy, size: 17),
                      color: colors.muted,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: current.text),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Source text copied.'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.canvas,
                    borderRadius: AppRadius.boxSm,
                    border: Border.all(color: colors.border),
                  ),
                  child: SelectableText(
                    current.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.9,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
