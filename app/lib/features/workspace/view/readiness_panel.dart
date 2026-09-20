/// The review-readiness column: how much of the inventory is selected, what
/// the extraction guarantees, and the flagged identifiers that need a look.
///
/// MOVED out of `document_review_view.dart`, where it was `_ReadinessPanel`.
/// Two things forced the move:
///
/// 1. At `ultra` and `cinema` widths this panel moves out of the content column
///    and into the shell's 360px right rail, which is built by
///    `WorkspaceShell` — a file that cannot import a private widget from a
///    sibling view.
/// 2. It used to take an `onInspectFlagged` callback purely so it could switch
///    the parent's sub-tab. Now that the sub-tab lives in
///    `workspaceTabProvider` the panel changes it itself, and the callback —
///    and with it the parent's `setState` dependency — is gone.
///
/// It is a `ConsumerWidget` with no parameters, so it renders identically in
/// the in-content column and in the rail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../models/workspace_tab.dart';
import '../view_model/workspace_tab_controller.dart';
import '../view_model/workspace_view_model.dart';
import 'source_sheet.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class ReadinessPanel extends ConsumerWidget {
  const ReadinessPanel({super.key});

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
                      'Tổng quan đánh giá',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  WBadge(
                    label: mockMode ? 'Mô phỏng' : 'Trực tuyến',
                    tint: mockMode ? WBadgeTint.amber : WBadgeTint.green,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Kiểm tra danh sách trước khi chấm điểm.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                ),
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
                    'mục đã chọn',
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
                    'Sẵn sàng chấm điểm',
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
                ('Đầy đủ ngữ cảnh Use Case', Icons.check_circle_outline),
                ('Bảo toàn trích dẫn gốc', Icons.check_circle_outline),
                ('Không cắt ngắn dữ liệu', Icons.check_circle_outline),
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
                              '${state.attentionCount} mục cần kiểm tra lại (Mã ID không khớp mẫu mặc định)',
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
                        'Các mục này vẫn được giữ lại. Hãy kiểm tra mã ID trước khi chấm.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.amber,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final unit
                              in state.units.where((u) => u.malformed).take(3))
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
                                    fontSize: AppType.micro,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      InkWell(
                        // Reads the tab notifier directly instead of calling
                        // back into the parent view: the panel is also rendered
                        // in the shell's right rail, where there is no parent
                        // view to call.
                        onTap: () => ref
                            .read(workspaceTabProvider.notifier)
                            .select(WorkspaceTab.inventory),
                        child: Text(
                          'Xem các mục cần kiểm tra →',
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
                          'Các mã ID đều đúng định dạng.',
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
                          ? 'Mô phỏng ngoại tuyến · không cần khóa API'
                          : 'Chấm qua máy chủ · đã đối chiếu trích dẫn',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => showSettingsModal(context, ref),
                    child: Text(
                      'Thay đổi',
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
                'Đánh giá có bằng chứng',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.brand,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Chỉ hiển thị lỗi có trích dẫn đối chiếu được với tài liệu gốc.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: () => showHelpModal(context, ref),
                child: Text(
                  'Cách đối chiếu trích dẫn →',
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
