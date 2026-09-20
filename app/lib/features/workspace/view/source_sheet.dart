/// Source sheet — the brief's source drawer, rebuilt as a bottom sheet on
/// phones and a side-anchored sheet on wide windows. Shows the unit's
/// metadata, its classification controls and the original source text with
/// copy-to-clipboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_breakpoint.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../data/checks/rubric_config.dart';
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
      initialChildSize: width >= AppBreakpoints.compactMaxWidth ? 0.9 : 0.82,
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
    final state = ref.watch(workspaceViewModelProvider);
    final current =
        state.units.where((u) => u.key == unit.key).firstOrNull ?? unit;
    final activeFinding = finding;

    // The preview the inventory row promised: this unit's score and every
    // verified issue against it, quote (where) and suggestion (how) inline.
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final result = state.result;
    final unitScore = result?.scores[current.key];
    final scored = <FindingRow>[];
    if (result != null) {
      if (activeFinding != null) {
        scored.add(activeFinding);
      }
      for (final row in result.findings) {
        if (row.unitKey == current.key && row.id != activeFinding?.id) {
          scored.add(row);
        }
      }
    }

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
                    'NGỮ CẢNH TÀI LIỆU GỐC',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng tài liệu gốc',
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
                      label: 'Trang ${current.pageIndex + 1}',
                      tint: WBadgeTint.green,
                    ),
                    if (current.malformed)
                      WBadge(label: 'ID sai định dạng', tint: WBadgeTint.amber),
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
                  current.section ?? 'Chưa phân loại',
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
                        'Mã ID chưa đúng định dạng và vẫn được giữ lại. Hãy chọn loại yêu cầu để đưa mục này vào lượt chấm.',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: current.kind.label,
                  decoration: InputDecoration(
                    labelText: 'Phân loại',
                    border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
                    isDense: true,
                  ),
                  items: [
                    for (final kind in UnitKind.values)
                      DropdownMenuItem(
                        value: kind.label,
                        child: Text(workspaceLabel(kind.label)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    viewModel.classifyUnit(
                      current.key,
                      UnitKind.fromLabel(value),
                    );
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
                      'Đưa vào lượt chấm',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: colors.brand,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // The per-unit review preview: score, then every verified
                // issue with its quote (where to fix) and suggestion (how).
                // The tapped finding leads; the rest keep the run's
                // severity-first order.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'KẾT QUẢ ĐÁNH GIÁ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.muted,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (unitScore != null)
                      WScoreChip(
                        score: unitScore,
                        passMark: rubric.passMark,
                        warnScore: rubric.warnScore,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (unitScore == null)
                  WInfoNote(
                    icon: Icons.help_outline,
                    text:
                        'Mục này chưa có điểm trong lượt chấm gần nhất. Hãy chọn mục để chấm và xem gợi ý sửa.',
                  )
                else if (scored.isEmpty)
                  WInfoNote(
                    icon: Icons.verified_outlined,
                    text:
                        'Chưa có lỗi được xác minh cho yêu cầu này. Điểm phản ánh chất lượng diễn đạt, chưa đảm bảo tính đầy đủ.',
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${scored.length} lỗi cần sửa tại đây',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final row in scored)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: WPanel(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    WBadge(
                                      label: workspaceLabel(row.severity.name),
                                      tint: row.severity == Severity.high
                                          ? WBadgeTint.amber
                                          : WBadgeTint.neutral,
                                    ),
                                    WBadge(
                                      label: workspaceLabel(row.typeLabel),
                                      tint: WBadgeTint.neutral,
                                    ),
                                    if (state.statusOf(row.id) !=
                                        FindingStatus.open)
                                      WBadge(
                                        label: workspaceLabel(
                                          state.statusOf(row.id).label,
                                        ),
                                        tint:
                                            state.statusOf(row.id) ==
                                                FindingStatus.fixed
                                            ? WBadgeTint.purple
                                            : WBadgeTint.neutral,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: colors.quoteBg,
                                    borderRadius: AppRadius.boxSm,
                                    border: Border(
                                      left: BorderSide(
                                        color: colors.quoteBar,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '"${row.quote}"',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.muted,
                                      height: 1.7,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  workspaceMessage(row.suggestion),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.muted,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nội dung tài liệu gốc',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sao chép nội dung gốc',
                      icon: const Icon(Icons.copy, size: 17),
                      color: colors.muted,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: current.text),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã sao chép nội dung gốc.'),
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
