import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_radius.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_icon.dart';
import 'package:srs_review_ai_admin_web/features/auth/presentation/viewmodels/current_user_view_model.dart';
import 'package:srs_review_ai_admin_web/features/dashboard/presentation/viewmodels/admin_dashboard_view_model.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/presentation/views/srs_reports_tab.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/presentation/views/crashlytics_tab.dart';
import 'package:srs_review_ai_admin_web/features/remote_config_editor/presentation/views/remote_config_tab.dart';
import 'package:srs_review_ai_admin_web/features/users_management/presentation/views/users_tab.dart';

/// Admin Dashboard View - Master-Detail Layout với Sidebar Navigation
class AdminDashboardView extends ConsumerWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(adminDashboardViewModelProvider);
    final dashboardViewModel = ref.read(
      adminDashboardViewModelProvider.notifier,
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        children: [
          // Side Navigation Rail / Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: dashboardState.isSidebarCollapsed ? 80 : 280,
            child: _buildSidebar(
              context,
              ref,
              dashboardState,
              dashboardViewModel,
            ),
          ),
          // Vertical Divider
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
          // Content Area
          Expanded(
            child: Column(
              children: [
                // Header
                _buildHeader(context, ref, dashboardState),
                const Divider(height: 1, thickness: 1, color: AppColors.line),
                // Tab Content
                Expanded(child: _buildContent(dashboardState.selectedTab)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    AdminDashboardState state,
    AdminDashboardViewModel viewModel,
  ) {
    return Container(
      color: AppColors.white,
      child: Column(
        children: [
          // Sidebar Header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Row(
              children: [
                const AppIcon('files', color: AppColors.brand, size: 28),
                if (!state.isSidebarCollapsed) ...[
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      'SRS Admin',
                      style: AppTypography.header.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              children: [
                _buildNavItem(
                  context,
                  icon: 'file-text',
                  label: 'Quản lý Báo cáo SRS',
                  tab: AdminTab.srsReports,
                  isSelected: state.selectedTab == AdminTab.srsReports,
                  isCollapsed: state.isSidebarCollapsed,
                  onTap: () => viewModel.selectTab(AdminTab.srsReports),
                ),
                _buildNavItem(
                  context,
                  icon: 'circle-alert',
                  label: 'Monitor Crashlytics',
                  tab: AdminTab.crashlytics,
                  isSelected: state.selectedTab == AdminTab.crashlytics,
                  isCollapsed: state.isSidebarCollapsed,
                  onTap: () => viewModel.selectTab(AdminTab.crashlytics),
                ),
                _buildNavItem(
                  context,
                  icon: 'settings',
                  label: 'Cấu hình Remote Config',
                  tab: AdminTab.remoteConfig,
                  isSelected: state.selectedTab == AdminTab.remoteConfig,
                  isCollapsed: state.isSidebarCollapsed,
                  onTap: () => viewModel.selectTab(AdminTab.remoteConfig),
                ),
                _buildNavItem(
                  context,
                  icon: 'users',
                  label: 'Danh sách Người dùng',
                  tab: AdminTab.users,
                  isSelected: state.selectedTab == AdminTab.users,
                  isCollapsed: state.isSidebarCollapsed,
                  onTap: () => viewModel.selectTab(AdminTab.users),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          // Sidebar Footer
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: IconButton(
              onPressed: () => viewModel.toggleSidebar(),
              icon: Icon(
                state.isSidebarCollapsed
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
                color: AppColors.muted,
              ),
              tooltip: state.isSidebarCollapsed
                  ? 'Mở rộng sidebar'
                  : 'Thu gọn sidebar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String icon,
    required String label,
    required AdminTab tab,
    required bool isSelected,
    required bool isCollapsed,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: isSelected ? AppColors.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? AppSpacing.m : AppSpacing.m,
              vertical: AppSpacing.m,
            ),
            child: Row(
              children: [
                AppIcon(
                  icon,
                  color: isSelected ? AppColors.brand : AppColors.muted,
                  size: 20,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.body.copyWith(
                        color: isSelected ? AppColors.brand : AppColors.ink,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    AdminDashboardState state,
  ) {
    final user = ref.watch(currentUserProvider).asData?.value;
    String title;
    switch (state.selectedTab) {
      case AdminTab.srsReports:
        title = 'Quản lý Báo cáo SRS';
        break;
      case AdminTab.crashlytics:
        title = 'Monitor Log Crashlytics';
        break;
      case AdminTab.remoteConfig:
        title = 'Cấu hình Tham số từ xa';
        break;
      case AdminTab.users:
        title = 'Danh sách Người dùng';
        break;
    }

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.header,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  user?.displayName.isNotEmpty == true
                      ? user!.displayName
                      : (user?.email ?? 'Admin'),
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brandSoft,
                backgroundImage: user?.photoUrl == null
                    ? null
                    : NetworkImage(user!.photoUrl!),
                child: user?.photoUrl != null
                    ? null
                    : Text(
                        (user?.displayName.isNotEmpty == true
                                ? user!.displayName
                                : user?.email ?? 'A')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: AppTypography.strong.copyWith(
                          color: AppColors.brand,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.s),
              IconButton(
                tooltip: 'Đăng xuất',
                onPressed: () async {
                  try {
                    await ref.read(authActionsProvider).signOut();
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đăng xuất thất bại: $error')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AdminTab tab) {
    switch (tab) {
      case AdminTab.srsReports:
        return const SrsReportsTab();
      case AdminTab.crashlytics:
        return const CrashlyticsTab();
      case AdminTab.remoteConfig:
        return const RemoteConfigTab();
      case AdminTab.users:
        return const UsersTab();
    }
  }
}
