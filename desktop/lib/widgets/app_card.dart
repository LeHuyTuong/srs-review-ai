import 'package:flutter/material.dart';
import 'package:srs_review_ai/core/theme/app/app_colors.dart';
import 'package:srs_review_ai/core/theme/app/app_corners.dart';
import 'package:srs_review_ai/core/theme/app/app_metrics.dart';
import 'package:srs_review_ai/core/theme/app/app_spacing.dart';

// Thẻ phẳng với viền và khoảng đệm tương đương Card.tsx, không tự thêm bóng.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.tinted = false,
    this.padding = const EdgeInsets.all(AppSpacing.l),
    super.key,
  });
  final Widget child;
  final bool tinted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: tinted ? AppColors.brandTint : AppColors.white,
      border: Border.all(color: AppColors.line, width: AppMetrics.border),
      borderRadius: AppCorners.card,
    ),
    child: Padding(
      padding: padding.add(const EdgeInsets.all(AppMetrics.border)),
      child: child,
    ),
  );
}
