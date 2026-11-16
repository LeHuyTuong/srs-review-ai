import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/widgets/stat_card.dart';

/// Số cột chia hết số ô để không có hàng cụt (6 ô → 6 hoặc 3 cột, không phải
/// 4 + 2), và mỗi ô không hẹp hơn [AppMetrics.statMinWidth]. Điện thoại giữ
/// 2 cột, tablet 3 cột như trước.
int statColumns({
  required int count,
  required double width,
  required double screenWidth,
}) {
  if (screenWidth < AppMetrics.tabletBreakpoint) return 2;
  if (screenWidth < AppMetrics.desktopBreakpoint) return 3;
  for (final c in [6, 5, 4, 3]) {
    if (c > count || count % c != 0) continue;
    final cell = (width - AppMetrics.gridGap * (c - 1)) / c;
    if (cell >= AppMetrics.statMinWidth) return c;
  }
  return 3;
}

// Mỗi hàng cao bằng ô dài nhất; số cột đổi theo chiều rộng màn hình và không cố định tỷ lệ thẻ.
class DashboardStats extends StatelessWidget {
  const DashboardStats({required this.stats, super.key});
  final List<DashboardStat> stats;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Thống kê tổng quan',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = statColumns(
          count: stats.length,
          width: constraints.maxWidth,
          screenWidth: MediaQuery.sizeOf(context).width,
        );
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
