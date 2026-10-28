import 'package:flutter/material.dart';

import 'package:srs_review_ai/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';

// Tóm tắt yêu cầu đúng thứ tự React; không suy luận kết quả AI từ trạng thái cũ.
class DashboardReviewRow extends StatelessWidget {
  const DashboardReviewRow({
    required this.request,
    required this.onOpen,
    super.key,
  });
  final DashboardRequest request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
      child: Row(
        spacing: AppSpacing.m,
        children: [
          const AppIcon('file-text', size: AppMetrics.iconSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(request.documentTitle, style: AppTypography.strong),
                    AppBadge(request.version),
                  ],
                ),
                Text(request.projectName),
                Text(
                  '${request.classCode} · ${request.groupName}',
                  style: AppTypography.muted,
                ),
                Text(request.aiLabel, style: AppTypography.muted),
                Text(request.relativeTime, style: AppTypography.muted),
              ],
            ),
          ),
          const AppIcon('chevron-right'),
        ],
      ),
    ),
  );
}
