import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/widgets/stat_card.dart';

// Mỗi hàng cao bằng ô dài nhất; số cột đổi theo chiều rộng màn hình và không cố định tỷ lệ thẻ.
class DashboardStats extends StatelessWidget {
  const DashboardStats({required this.stats, super.key});
  final List<DashboardStat> stats;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Thống kê tổng quan',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            MediaQuery.sizeOf(context).width >= AppMetrics.tabletBreakpoint
            ? 3
            : 2;
        return Column(
          spacing: AppMetrics.gridGap,
          children: [
            for (var offset = 0; offset < stats.length; offset += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppMetrics.gridGap,
                  children: [
                    for (var index = offset; index < offset + columns; index++)
                      Expanded(
                        child: index < stats.length
                            ? StatCard(
                                label: stats[index].label,
                                value: stats[index].value,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
