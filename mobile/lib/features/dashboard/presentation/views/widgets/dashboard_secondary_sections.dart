import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_disclosure.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_review_row.dart';

// Các mục thu gọn phụ dùng cùng dữ liệu và thứ tự nội dung của Dashboard React.
class DashboardSecondarySections extends StatelessWidget {
  const DashboardSecondarySections({
    required this.state,
    required this.onNavigate,
    super.key,
  });
  final DashboardState state;
  final ValueChanged<String> onNavigate;

  Widget _link(
    String label,
    String route, {
    Widget? trailing,
    TextStyle? style,
  }) => InkWell(
    onTap: () => onNavigate(route),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.xl),
        child: Row(
          spacing: AppSpacing.m,
          children: [
            Expanded(child: Text(label, style: style)),
            ?trailing,
            const AppIcon('chevron-right', size: AppMetrics.iconSmall),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    spacing: AppSpacing.l,
    children: [
      Container(
        decoration: const BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: AppColors.line),
          ),
        ),
        child: _link(
          'Đăng ký dự án',
          '/project-registrations',
          style: AppTypography.strong,
          trailing: AppBadge(
            '${state.pendingRegistrations} chờ duyệt',
            tone: state.pendingRegistrations > 0 ? 'amber' : 'neutral',
          ),
        ),
      ),
      AppDisclosure(
        title: 'Đang đánh giá (${state.inReview.length})',
        child: Column(
          children: [
            if (state.inReview.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                child: Text(
                  'Không có tài liệu đang đánh giá.',
                  style: AppTypography.muted,
                ),
              ),
            for (final request in state.inReview)
              DashboardReviewRow(
                request: request,
                onOpen: () => onNavigate('/reviews/${request.id}'),
              ),
          ],
        ),
      ),
      AppDisclosure(
        title: 'Truy cập nhanh',
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
              child: Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.m,
                children: [
                  for (final item in [
                    ('Lớp phụ trách', state.trackedClasses),
                    ('Đang thực hiện', state.activeProjects),
                    ('Đã lưu trữ', state.archivedProjects),
                    ('Chờ sinh viên sửa', state.needsRevision),
                    ('Sắp đến hạn nộp', state.dueSoon),
                  ])
                    SizedBox(
                      width: AppMetrics.semesterWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$1, style: AppTypography.muted),
                          Text('${item.$2}', style: AppTypography.strong),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            for (final item in [
              ('Học kỳ', '/semesters', '${state.snapshot.semesters.length}'),
              ('Môn học', '/courses', '${state.snapshot.courseCount}'),
              ('Lớp', '/classes', '${state.snapshot.classes.length}'),
              ('Sinh viên', '/students', '${state.snapshot.studentCount}'),
              ('Nhóm', '/groups', '${state.snapshot.groupClasses.length}'),
              ('Bộ quy tắc', '/rule-sets', ''),
            ]) ...[
              _link(
                item.$1,
                item.$2,
                trailing: Text(item.$3, style: AppTypography.muted),
              ),
              const Divider(),
            ],
          ],
        ),
      ),
      AppDisclosure(
        title: 'Dự án cần chú ý (${state.attention.length})',
        child: Column(
          children: [
            for (final item in state.attention)
              InkWell(
                onTap: () => onNavigate('/projects/${item.projectId}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
                  child: Row(
                    spacing: AppSpacing.m,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: AppSpacing.s,
                          children: [
                            AppBadge(item.label, tone: item.tone),
                            Text(item.title, style: AppTypography.strong),
                            Text(item.detail, style: AppTypography.muted),
                          ],
                        ),
                      ),
                      const AppIcon(
                        'chevron-right',
                        size: AppMetrics.iconSmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
