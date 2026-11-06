import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_text_input.dart';
import 'package:srs_review_ai_admin_web/features/academic/domain/models/academic_models.dart';
import 'package:srs_review_ai_admin_web/features/academic/presentation/viewmodels/academic_view_model.dart';

/// Tab Quản lý Lớp — đọc realtime collection `classes` (Firestore snapshots).
class ClassesTab extends ConsumerWidget {
  const ClassesTab({super.key});

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
                      hintText: 'Tìm kiếm lớp theo tên hoặc mã lớp...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: viewModel.setSearchQuery,
                  ),
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
                        Expanded(flex: 3, child: _Header('Lớp')),
                        Expanded(flex: 2, child: _Header('Môn học')),
                        Expanded(flex: 1, child: _Header('Nhóm')),
                        Expanded(flex: 1, child: _Header('Sinh viên')),
                        Expanded(flex: 1, child: _Header('Dự án')),
                        Expanded(flex: 1, child: _Header('Chờ chấm')),
                        Expanded(flex: 1, child: _Header('Trạng thái')),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : state.error != null
                        ? _ErrorView(
                            error: state.error!,
                            onRetry: viewModel.refresh,
                          )
                        : state.filteredClasses.isEmpty
                        ? const Center(
                            child: Text('Chưa có lớp nào trên Firestore.'),
                          )
                        : ListView.builder(
                            itemCount: state.filteredClasses.length,
                            itemBuilder: (context, index) => _ClassRow(
                              room: state.filteredClasses[index],
                              courseLabel: _courseLabel(
                                state,
                                state.filteredClasses[index].courseId,
                              ),
                            ),
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

  String _courseLabel(AcademicState state, String courseId) {
    for (final course in state.courses) {
      if (course.id == courseId) {
        return course.code.isEmpty ? course.name : course.code;
      }
    }
    return courseId.isEmpty ? '—' : courseId;
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600));
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Lỗi: $error', style: const TextStyle(color: AppColors.danger)),
        const SizedBox(height: AppSpacing.m),
        AppButton(label: 'Thử lại', onPressed: onRetry),
      ],
    ),
  );
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.room, required this.courseLabel});
  final ClassRoom room;
  final String courseLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              room.name.isEmpty ? room.code : room.name,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              courseLabel,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('${room.groupCount}', style: AppTypography.body),
          ),
          Expanded(
            flex: 1,
            child: Text('${room.studentCount}', style: AppTypography.body),
          ),
          Expanded(
            flex: 1,
            child: Text('${room.projectCount}', style: AppTypography.body),
          ),
          Expanded(
            flex: 1,
            child: Text('${room.pendingReviews}', style: AppTypography.body),
          ),
          Expanded(
            flex: 1,
            child: AppBadge(
              room.archived ? 'Đã lưu trữ' : 'Đang hoạt động',
              tone: room.archived ? 'neutral' : 'olive',
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}
