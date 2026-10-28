import 'package:flutter/material.dart';
import 'package:srs_review_ai/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai/features/dashboard/presentation/viewmodels/dashboard_view_model.dart';
import 'package:srs_review_ai/features/dashboard/presentation/views/widgets/dashboard_review_row.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_disclosure.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';
import 'package:srs_review_ai/widgets/app_states.dart';

// Việc cần làm chỉ nhận danh sách đã lọc; giới hạn ba dòng đầu theo React.
class DashboardTasks extends StatelessWidget {
  const DashboardTasks({
    required this.state,
    required this.onNavigate,
    super.key,
  });
  final DashboardState state;
  final ValueChanged<String> onNavigate;

  Widget _rows(List<DashboardRequest> requests) => Column(
    children: [
      for (var i = 0; i < requests.length; i++) ...[
        if (i > 0) const Divider(),
        DashboardReviewRow(
          request: requests[i],
          onOpen: () => onNavigate('/reviews/${requests[i].id}'),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.s,
    children: [
      Text('Việc cần làm', style: AppTypography.blockTitle),
      if (state.waiting.isEmpty)
        const AppEmptyState(title: 'Không còn tài liệu chờ đánh giá')
      else ...[
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          child: _rows(DashboardTaskPresentation(state).preview),
        ),
        InkWell(
          onTap: () => onNavigate('/reviews'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Xem ${state.waiting.length} yêu cầu',
                  style: AppTypography.strong.copyWith(color: AppColors.brand),
                ),
                const AppIcon(
                  'chevron-right',
                  size: AppMetrics.iconSmall,
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
        ),
        if (state.waiting.length > 3)
          AppDisclosure(
            title: 'Yêu cầu khác (${state.waiting.length - 3})',
            child: _rows(DashboardTaskPresentation(state).remaining),
          ),
      ],
    ],
  );
}
