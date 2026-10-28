import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

// Phần đầu ứng dụng căn trái theo React và dùng SafeArea để tránh vùng hệ thống.
class MobileHeader extends StatelessWidget implements PreferredSizeWidget {
  const MobileHeader({required this.onHome, super.key});
  final VoidCallback onHome;
  @override
  Size get preferredSize =>
      const Size.fromHeight(AppSpacing.headerHeight + AppMetrics.border);

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    child: SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: AppSpacing.headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: onHome,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.tapMin,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          'files',
                          size: AppMetrics.iconLarge,
                          color: AppColors.brand,
                        ),
                        const SizedBox(width: AppMetrics.gridGap),
                        Flexible(
                          child: Text(
                            'SRS Đánh giá AI',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.header,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(
            height: AppMetrics.border,
            thickness: AppMetrics.border,
            color: AppColors.line,
          ),
        ],
      ),
    ),
  );
}
