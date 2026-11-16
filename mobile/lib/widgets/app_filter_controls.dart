import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

// Bộ chọn gọn trong thanh lọc, giữ kích thước theo nhãn và vùng chạm 48dp.
class AppSelectButton extends StatelessWidget {
  const AppSelectButton({
    required this.label,
    required this.options,
    required this.onChanged,
    this.selected = false,
    this.compact = false,
    super.key,
  });
  final String label;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final bool selected;
  final bool compact;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final e in options.entries)
        PopupMenuItem(value: e.key, child: Text(e.value)),
    ],
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.s : AppSpacing.m,
      ),
      decoration: BoxDecoration(
        color: selected ? AppColors.brandSoft : AppColors.white,
        border: Border.all(color: selected ? AppColors.brand : AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: compact ? AppSpacing.xs : AppSpacing.s,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.brand : AppColors.ink,
              ),
            ),
          ),
          AppIcon(
            'chevron-down',
            size: compact ? AppMetrics.formIcon : AppMetrics.icon,
          ),
        ],
      ),
    ),
  );
}

// Chip lọc cuộn ngang, nhấn để gỡ đúng một điều kiện như SmartFilterBar.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({required this.label, required this.onRemove, super.key});
  final String label;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onRemove,
    borderRadius: BorderRadius.circular(AppSpacing.huge),
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        border: Border.all(color: AppColors.brand.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(AppSpacing.huge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xs,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(color: AppColors.brand),
          ),
          const AppIcon('x', color: AppColors.brand),
        ],
      ),
    ),
  );
}
