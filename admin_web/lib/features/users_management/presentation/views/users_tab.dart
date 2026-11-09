import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_text_input.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/features/users_management/presentation/viewmodels/users_view_model.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

/// Tab 4: Danh sách Người dùng
class UsersTab extends ConsumerWidget {
  const UsersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(usersViewModelProvider);
    final viewModel = ref.read(usersViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search Bar
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiếm theo tên, email hoặc UID...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => viewModel.setSearchQuery(value),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                AppButton(
                  label: 'Làm mới',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => viewModel.refresh(),
                  variant: AppButtonVariant.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          // Data Table
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                      vertical: AppSpacing.s,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.subtle,
                      border: Border(
                        bottom: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Người dùng',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Email',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'UID',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Vai trò',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Ngày đăng ký',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Đăng nhập cuối',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Table Body
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
                                      style: const TextStyle(color: AppColors.danger),
                                    ),
                                    const SizedBox(height: AppSpacing.m),
                                    AppButton(
                                      label: 'Thử lại',
                                      onPressed: () => viewModel.refresh(),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: state.filteredUsers.length,
                                itemBuilder: (context, index) {
                                  final user = state.filteredUsers[index];
                                  return _buildUserRow(context, user);
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

  Widget _buildUserRow(BuildContext context, AppUser user) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.m,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.brandSoft,
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName.substring(0, 1).toUpperCase()
                          : '?',
                      style: AppTypography.strong.copyWith(color: AppColors.brand),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Tooltip(
                      message: user.displayName,
                      child: Text(
                        user.displayName,
                        style: AppTypography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Tooltip(
                message: user.email,
                child: Text(
                  user.email,
                  style: AppTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Tooltip(
                message: user.uid,
                child: Text(
                  user.uid.length > 8 ? '${user.uid.substring(0, 8)}...' : user.uid,
                  style: AppTypography.body.copyWith(fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppBadge(
                  user.roleLabel,
                  tone: user.isAdminRole
                      ? 'danger'
                      : user.isTeacherRole
                          ? 'brand'
                          : 'olive',
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                '${user.registrationDate.day}/${user.registrationDate.month}/${user.registrationDate.year}',
                style: AppTypography.body,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                '${user.lastSignIn.day}/${user.lastSignIn.month}/${user.lastSignIn.year} ${user.lastSignIn.hour}:${user.lastSignIn.minute.toString().padLeft(2, '0')}',
                style: AppTypography.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
