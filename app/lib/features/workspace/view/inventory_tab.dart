/// Inventory tab — searchable, filterable, paginated list of requirement
/// units with selection. The brief renders a desktop table; here every row
/// is a tappable card that works at phone width.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../models/workspace_unit.dart';
import '../view_model/workspace_view_model.dart';
import 'source_sheet.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class InventoryTab extends ConsumerStatefulWidget {
  const InventoryTab({super.key});

  @override
  ConsumerState<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends ConsumerState<InventoryTab> {
  String _query = '';
  String _kind = 'All types';
  String _status = 'All units';
  int _page = 1;

  static const int _rowsPerPage = 8;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    final filtered = _filtered(state.units);
    final pageCount = (filtered.length / _rowsPerPage).ceil().clamp(1, 1 << 31);
    final safePage = _page.clamp(1, pageCount);
    final visible = filtered
        .skip((safePage - 1) * _rowsPerPage)
        .take(_rowsPerPage)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: TextField(
                  onChanged: (value) => setState(() {
                    _query = value;
                    _page = 1;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Search ID or requirement…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.boxSm,
                    ),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _kind,
                items: [
                  for (final label in [
                    'All types',
                    ...UnitKind.values.map((k) => k.label),
                  ])
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                underline: const SizedBox.shrink(),
                borderRadius: AppRadius.boxSm,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.muted,
                ),
                onChanged: (value) => setState(() {
                  _kind = value ?? 'All types';
                  _page = 1;
                }),
              ),
              DropdownButton<String>(
                value: _status,
                items: [
                  for (final label in const [
                    'All units',
                    'Needs attention',
                    'Selected',
                    'Reviewed',
                  ])
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                underline: const SizedBox.shrink(),
                borderRadius: AppRadius.boxSm,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.muted,
                ),
                onChanged: (value) => setState(() {
                  _status = value ?? 'All units';
                  _page = 1;
                }),
              ),
            ],
          ),
        ),
        if (_status != 'All units' || _kind != 'All types')
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                InputChip(
                  label: Text(
                    _status != 'All units' ? _status : _kind,
                  ),
                  onDeleted: () => setState(() {
                    _status = 'All units';
                    _kind = 'All types';
                    _page = 1;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colors.muted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _status == 'Needs attention'
                      ? 'Unclassified requirements'
                      : 'Requirements inventory',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${filtered.length} units',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        // The selection bar sits ABOVE the list, not below it: with 65 demo
        // units the Run-review CTA used to land ~700px below the fold on a
        // phone (y=1562 at 390x844) — measured, unreachable, and the reason
        // users reported "cannot press Run review".
        Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.selectionBarBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.sageBg,
                  border: Border.all(color: colors.border),
                ),
                child: Icon(Icons.check, size: 14, color: colors.sage),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${state.selectedCount} units selected',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      state.attentionCount > 0
                          ? '${state.attentionCount} flagged units are preserved for your review'
                          : 'All detected units are accounted for',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              WButton.primary(
                label: 'Run review',
                icon: Icons.auto_awesome,
                onPressed: state.selectedCount == 0 || state.isRunning
                    ? null
                    : () => showReviewModal(context, ref),
              ),
            ],
          ),
        ),
        if (visible.isEmpty)
          WEmptyState(
            icon: Icons.search,
            title: 'No matching requirements',
            message: 'Try another keyword or reset your filters.',
          )
        else
          Column(
            children: [
              for (final unit in visible)
                _UnitRow(
                  unit: unit,
                  onOpen: () => showSourceSheet(context, ref, unit),
                  onToggle: (value) =>
                      viewModel.setUnitSelected(unit.key, value),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  filtered.isEmpty
                      ? ''
                      : 'Showing ${(safePage - 1) * _rowsPerPage + 1}–'
                          '${((safePage - 1) * _rowsPerPage) + visible.length} '
                          'of ${filtered.length} units',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: safePage <= 1
                    ? null
                    : () => setState(() => _page = safePage - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
                color: colors.muted,
              ),
              Text(
                '$safePage / $pageCount',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: safePage >= pageCount
                    ? null
                    : () => setState(() => _page = safePage + 1),
                icon: const Icon(Icons.chevron_right, size: 18),
                color: colors.muted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<WorkspaceUnit> _filtered(List<WorkspaceUnit> units) {
    final query = _query.toLowerCase();
    return units
        .where(
          (u) =>
              (_kind == 'All types' || u.kind.label == _kind) &&
              (_status == 'All units' ||
                  (_status == 'Needs attention' && u.malformed) ||
                  (_status == 'Selected' && u.selected) ||
                  (_status == 'Reviewed' && u.status == UnitStatus.reviewed)) &&
              ('${u.id} ${u.title} ${u.section ?? ''}'.toLowerCase())
                  .contains(query),
        )
        .toList(growable: false);
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.onOpen,
    required this.onToggle,
  });

  final WorkspaceUnit unit;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final (Color statusColor, String statusLabel) = switch ((
      unit.malformed,
      unit.status,
    )) {
      (true, _) => (colors.amber, 'Check ID'),
      (false, UnitStatus.reviewed) => (colors.brand, 'Reviewed'),
      (false, UnitStatus.failed) => (colors.amber, 'Failed'),
      (false, UnitStatus.skipped) => (colors.muted, 'Skipped'),
      (false, UnitStatus.pending) => (colors.sage, unit.selected ? 'Ready' : 'Skipped'),
    };

    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border.withValues(alpha: 0.6))),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        // Phones drop the page column (the source sheet carries it); wide
        // screens keep every column from the brief's table.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final columns = <Widget>[
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: unit.selected,
                  onChanged: (value) => onToggle(value ?? false),
                  activeColor: colors.brand,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(
                width: 74,
                child: Text(
                  unit.id,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  unit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The type badge used to take its natural width, which pushed
              // the fixed-width page/status columns 14px past the right edge
              // on a 390px-wide phone. Let it shrink instead; the unit title
              // already carries the meaning.
              Flexible(
                child: WBadge(
                  label: unit.kind.label,
                  tint: unit.kind == UnitKind.unknown
                      ? WBadgeTint.amber
                      : unit.kind == UnitKind.businessRule
                      ? WBadgeTint.purple
                      : WBadgeTint.neutral,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!compact) ...[
                SizedBox(
                  width: 52,
                  child: Text(
                    'p. ${unit.pageIndex + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: 72,
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 4, color: statusColor),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: colors.muted),
            ];
            return Row(children: columns);
          },
        ),
      ),
    );
  }
}
