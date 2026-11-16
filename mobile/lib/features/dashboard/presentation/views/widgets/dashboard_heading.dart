import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

// Lời chào và bộ chọn học kỳ từ dữ liệu ViewModel; chỉ phát sự kiện chọn ID.
class DashboardHeading extends StatelessWidget {
  const DashboardHeading({
    required this.state,
    required this.onSemesterChanged,
    super.key,
  });
  final DashboardState state;
  final ValueChanged<String> onSemesterChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Xin chào, ${state.snapshot.userName.trim().isEmpty ? 'Giảng viên' : state.snapshot.userName}',
        style: AppTypography.greeting,
      ),
      const SizedBox(height: AppMetrics.greetingGap),
      Text(
        state.snapshot.role.trim().isEmpty ? 'Giảng viên' : state.snapshot.role,
        style: AppTypography.role,
      ),
      const SizedBox(height: AppSpacing.m),
      SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            Text('Tổng quan', style: AppTypography.dashboardTitle),
            SizedBox(
              width: AppMetrics.semesterWidth,
              child: Semantics(
                label: 'Học kỳ đang xem',
                child: DropdownButtonFormField<String>(
                  key: ValueKey(state.semesterId),
                  initialValue: state.semesterId,
                  isExpanded: true,
                  icon: const AppIcon(
                    'chevron-down',
                    size: AppSpacing.m,
                    color: AppColors.ink,
                  ),
                  style: AppTypography.body,
                  decoration: const InputDecoration(
                    constraints: BoxConstraints(minHeight: AppSpacing.tapMin),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tất cả học kỳ'),
                    ),
                    for (final semester in state.snapshot.semesters)
                      DropdownMenuItem(
                        value: semester.id,
                        child: Text(semester.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSemesterChanged(value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
