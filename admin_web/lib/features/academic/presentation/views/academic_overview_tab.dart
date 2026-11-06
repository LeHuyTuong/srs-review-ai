import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/features/academic/presentation/viewmodels/academic_view_model.dart';

/// Tab Tiến độ & Tổng hợp: số liệu tính trực tiếp từ Firestore
/// streams của `classes` + `projects` nên cập nhật ngay khi Mobile thao tác.
class AcademicOverviewTab extends ConsumerWidget {
  const AcademicOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(academicViewModelProvider);
    final viewModel = ref.read(academicViewModelProvider.notifier);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Lỗi: ${state.error}',
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.m),
            AppButton(label: 'Thử lại', onPressed: viewModel.refresh),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tiến độ tổng hợp theo thời gian thực',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            AppButton(
              label: 'Làm mới',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: viewModel.refresh,
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.m,
          children: [
            _StatCard(
              label: 'Môn học',
              value: '${state.courses.length}',
              tone: AppColors.brand,
            ),
            _StatCard(
              label: 'Lớp đang hoạt động',
              value: '${state.activeClasses}',
              tone: AppColors.brand,
            ),
            _StatCard(
              label: 'Nhóm sinh viên',
              value: '${state.totalGroups}',
              tone: AppColors.brand,
            ),
            _StatCard(
              label: 'Sinh viên',
              value: '${state.totalStudents}',
              tone: AppColors.brand,
            ),
            _StatCard(
              label: 'Tài liệu chờ chấm',
              value: '${state.pendingReviews}',
              tone: AppColors.amber,
            ),
            _StatCard(
              label: 'Dự án chờ duyệt',
              value: '${state.pendingProjects}',
              tone: AppColors.amber,
            ),
            _StatCard(
              label: 'Dự án đã duyệt',
              value: '${state.approvedProjects}',
              tone: AppColors.olive,
            ),
            _StatCard(
              label: 'Dự án cần chỉnh sửa',
              value: '${state.rejectedProjects}',
              tone: AppColors.rust,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tỉ lệ duyệt đề tài', style: AppTypography.strong),
              const SizedBox(height: AppSpacing.s),
              Text(
                '${(state.approvalRate * 100).toStringAsFixed(0)}% dự án đã được duyệt'
                ' (${state.approvedProjects}/${state.projects.length})',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.approvalRate,
                  minHeight: 10,
                  backgroundColor: AppColors.subtle,
                  valueColor: const AlwaysStoppedAnimation(AppColors.olive),
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              Text('Tiến độ trung bình của dự án', style: AppTypography.strong),
              const SizedBox(height: AppSpacing.s),
              Text(
                '${state.averageProgress}%',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.averageProgress / 100,
                  minHeight: 10,
                  backgroundColor: AppColors.subtle,
                  valueColor: const AlwaysStoppedAnimation(AppColors.brand),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.tone,
  });
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              value,
              style: AppTypography.header.copyWith(color: tone, fontSize: 28),
            ),
          ],
        ),
      ),
    );
  }
}
