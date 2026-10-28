import 'package:flutter/material.dart';

import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_radius.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';

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
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Padding(
      padding: padding.add(const EdgeInsets.all(AppMetrics.border)),
      child: child,
    ),
  );
}
