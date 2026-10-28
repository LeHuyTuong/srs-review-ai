import 'package:flutter/material.dart';

import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';

// Nhãn luôn có chữ; tone chỉ quyết định cặp màu tương ứng Badge.tsx.
class AppBadge extends StatelessWidget {
  const AppBadge(
    this.label, {
    this.tone = 'neutral',
    this.compact = false,
    super.key,
  });
  final bool compact;
  final String label, tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      'brand' => (AppColors.brandSoft, AppColors.brand),
      'olive' => (AppColors.oliveSoft, AppColors.olive),
      'amber' => (AppColors.amberSoft, AppColors.amber),
      'rust' => (AppColors.rustSoft, AppColors.rust),
      'danger' => (AppColors.dangerSoft, AppColors.danger),
      _ => (AppColors.subtle, AppColors.muted),
    };
    return Container(
      constraints: compact
          ? const BoxConstraints(minWidth: AppMetrics.labCodeWidth)
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppMetrics.statGap : AppSpacing.s,
        vertical: compact
            ? AppMetrics.compactBadgePadding
            : AppMetrics.badgePadding,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppMetrics.badgeRadius),
      ),
      child: Text(
        label,
        textAlign: compact ? TextAlign.center : null,
        style: (compact ? AppTypography.strong : AppTypography.badge).copyWith(
          color: foreground,
        ),
      ),
    );
  }
}
