import 'package:flutter/material.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/group_summary_card.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_states.dart';
import 'package:srs_review_ai/widgets/stat_card.dart';

// Tổng quan lớp hiển thị thống kê và tình trạng nhóm từ bản chụp dữ liệu học vụ.
class ClassOverview extends StatelessWidget {
  const ClassOverview({
    required this.snapshot,
    required this.room,
    required this.onNavigate,
    super.key,
  });
  final AcademicSnapshot snapshot;
  final ClassRoom room;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final groups = snapshot.classGroups(room.id);
    final students = snapshot.classStudents(room.id);
    final stats = [
      (students.isEmpty ? room.studentCount : students.length, 'Sinh viên'),
      (groups.length, 'Nhóm'),
      (snapshot.classProjects(room.id).length, 'Dự án'),
      (snapshot.classReviews(room).length, 'Chờ / đang đánh giá'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          spacing: AppSpacing.m,
          children: [
            for (var i = 0; i < stats.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.m,
                  children: [
                    for (var j = i; j < i + 2; j++)
                      Expanded(
                        child: StatCard(label: stats[j].$2, value: stats[j].$1),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Text('Tình trạng nhóm', style: AppTypography.sectionHeading),
        const SizedBox(height: AppSpacing.m),
        if (groups.isEmpty)
          const AppEmptyState(title: 'Chưa có nhóm nào')
        else
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                for (final g in groups)
                  InkWell(
                    onTap: () => onNavigate('/groups/${g.id}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      decoration: BoxDecoration(
                        border: g.id == groups.last.id
                            ? null
                            : const Border(
                                bottom: BorderSide(color: AppColors.line),
                              ),
                      ),
                      child: Row(
                        spacing: AppSpacing.m,
                        children: [
                          SizedBox(
                            width: AppMetrics.groupNameWidth,
                            child: Text(g.name, style: AppTypography.strong),
                          ),
                          Expanded(
                            child: AcademicProgress(
                              value: g.integer('progress'),
                            ),
                          ),
                          AppBadge(
                            '${((snapshot.data['groupHealthMeta'] as AcademicJson)[g.text('health')] as AcademicJson?)?['label'] ?? ''}',
                            tone:
                                '${((snapshot.data['groupHealthMeta'] as AcademicJson)[g.text('health')] as AcademicJson?)?['tone'] ?? 'neutral'}',
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
}
