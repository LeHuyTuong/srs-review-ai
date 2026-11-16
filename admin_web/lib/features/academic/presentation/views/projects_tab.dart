import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_text_input.dart';
import 'package:srs_review_ai_admin_web/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_admin_web/features/auth/presentation/viewmodels/current_user_view_model.dart';

/// Tab Quản lý Dự án — đọc realtime collection `projects`; trạng thái duyệt
/// (approved/rejected) do Giảng viên thao tác trên Mobile ghi xuống Firestore.
class ProjectsTab extends ConsumerWidget {
  const ProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(academicViewModelProvider);
    final viewModel = ref.read(academicViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiếm đề tài theo tên hoặc giảng viên...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: viewModel.setSearchQuery,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                AppButton(
                  label: 'Đồng bộ giảng viên',
                  icon: const Icon(Icons.sync, size: 18),
                  onPressed: () async {
                    final user = ref.read(currentUserProvider).asData?.value;
                    final name = user?.displayName.trim() ?? '';
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Chưa đăng nhập: không có tên giảng viên.',
                          ),
                        ),
                      );
                      return;
                    }
                    try {
                      await viewModel.syncLecturer(name);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Đã đồng bộ: $name')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  variant: AppButtonVariant.secondary,
                ),
                const SizedBox(width: AppSpacing.m),
                AppButton(
                  label: 'Làm mới',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: viewModel.refresh,
                  variant: AppButtonVariant.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: const BoxDecoration(
                      color: AppColors.subtle,
                      border: Border(bottom: BorderSide(color: AppColors.line)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: _Header('Đề tài')),
                        Expanded(flex: 2, child: _Header('Lớp')),
                        Expanded(flex: 2, child: _Header('Giảng viên')),
                        Expanded(flex: 1, child: _Header('Tiến độ')),
                        Expanded(flex: 2, child: _Header('Trạng thái duyệt')),
                        Expanded(flex: 3, child: _Header('Phản hồi')),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : state.error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Lỗi: ${state.error}',
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.m),
                                AppButton(
                                  label: 'Thử lại',
                                  onPressed: viewModel.refresh,
                                ),
                              ],
                            ),
                          )
                        : state.filteredProjects.isEmpty
                        ? const Center(
                            child: Text('Chưa có dự án nào trên Firestore.'),
                          )
                        : ListView.builder(
                            itemCount: state.filteredProjects.length,
                            itemBuilder: (context, index) {
                              final project = state.filteredProjects[index];
                              return Container(
                                padding: const EdgeInsets.all(AppSpacing.m),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: AppColors.line),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        project.name.isEmpty
                                            ? project.id
                                            : project.name,
                                        style: AppTypography.body,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        state.classLabel(project.classId),
                                        style: AppTypography.body,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        project.lecturer,
                                        style: AppTypography.body,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        '${project.progress}%',
                                        style: AppTypography.body,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: AppBadge(
                                        project.statusLabel,
                                        tone: project.statusTone,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        project.feedback.isEmpty
                                            ? '—'
                                            : project.feedback,
                                        style: AppTypography.body.copyWith(
                                          color: AppColors.muted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600));
}
