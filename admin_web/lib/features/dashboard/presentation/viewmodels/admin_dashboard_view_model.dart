import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Enum đại diện các tab trong Admin Web Dashboard
enum AdminTab {
  srsReports, // Tab 1: Quản lý Báo cáo SRS
  crashlytics, // Tab 2: Monitor Log Crashlytics
  remoteConfig, // Tab 3: Cấu hình Tham số từ xa
  users, // Tab 4: Danh sách Người dùng
  notifications, // Tab 5: Gửi thông báo đẩy (FCM)
  analytics, // Tab 6: Thống kê Analytics
}

/// State cho Admin Dashboard
class AdminDashboardState {
  const AdminDashboardState({
    this.selectedTab = AdminTab.srsReports,
    this.isSidebarCollapsed = false,
  });

  final AdminTab selectedTab;
  final bool isSidebarCollapsed;

  AdminDashboardState copyWith({
    AdminTab? selectedTab,
    bool? isSidebarCollapsed,
  }) {
    return AdminDashboardState(
      selectedTab: selectedTab ?? this.selectedTab,
      isSidebarCollapsed: isSidebarCollapsed ?? this.isSidebarCollapsed,
    );
  }
}

/// ViewModel quản lý trạng thái Admin Dashboard
class AdminDashboardViewModel extends Notifier<AdminDashboardState> {
  @override
  AdminDashboardState build() {
    return const AdminDashboardState();
  }

  void selectTab(AdminTab tab) {
    state = state.copyWith(selectedTab: tab);
  }

  void toggleSidebar() {
    state = state.copyWith(isSidebarCollapsed: !state.isSidebarCollapsed);
  }

  void collapseSidebar() {
    state = state.copyWith(isSidebarCollapsed: true);
  }

  void expandSidebar() {
    state = state.copyWith(isSidebarCollapsed: false);
  }
}

/// Provider cho Admin Dashboard ViewModel
final adminDashboardViewModelProvider =
    NotifierProvider<AdminDashboardViewModel, AdminDashboardState>(
  AdminDashboardViewModel.new,
);
