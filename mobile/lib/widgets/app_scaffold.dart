import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/current_user_view_model.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_radius.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/mobile_header.dart';

/// Quyết định bố cục theo chiều rộng: điện thoại giữ header + bottom nav,
/// màn rộng (web/desktop) dùng sidebar + top bar kiểu dashboard quản trị.
abstract final class AppLayout {
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppMetrics.desktopBreakpoint;

  static double contentMaxWidth(BuildContext context) => isDesktop(context)
      ? AppMetrics.desktopContentMaxWidth
      : AppMetrics.contentMaxWidth;
}

/// Trạng thái thu gọn sidebar sống qua các lần chuyển trang.
final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsed, bool>(
  SidebarCollapsed.new,
);

class SidebarCollapsed extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

typedef _NavItem = ({String path, String label, String icon});

/// Menu desktop chỉ trỏ tới route đã có trong `app.dart`.
const _sections = <({String? title, List<_NavItem> items})>[
  (
    title: null,
    items: [(path: '/dashboard', label: 'Tổng quan', icon: 'layout-dashboard')],
  ),
  (
    title: 'ĐÁNH GIÁ',
    items: [
      (path: '/reviews', label: 'Yêu cầu đánh giá', icon: 'file-check-2'),
      (path: '/review-history', label: 'Lịch sử đánh giá', icon: 'clock'),
      (path: '/documents', label: 'Tài liệu', icon: 'file-text'),
      (path: '/rule-sets', label: 'Bộ quy tắc', icon: 'sliders-horizontal'),
    ],
  ),
  (
    title: 'DỰ ÁN',
    items: [
      (path: '/projects', label: 'Dự án', icon: 'folder'),
      (
        path: '/project-registrations',
        label: 'Đăng ký dự án',
        icon: 'folder-plus',
      ),
      (path: '/groups', label: 'Nhóm sinh viên', icon: 'users'),
    ],
  ),
  (
    title: 'ĐÀO TẠO',
    items: [
      (path: '/semesters', label: 'Học kỳ', icon: 'calendar'),
      (path: '/courses', label: 'Môn học & Đợt học', icon: 'book-open'),
      (path: '/classes', label: 'Lớp học', icon: 'school'),
      (path: '/students', label: 'Sinh viên', icon: 'graduation-cap'),
    ],
  ),
  (
    title: 'HỆ THỐNG',
    items: [
      (path: '/notifications', label: 'Thông báo', icon: 'inbox'),
      (path: '/profile', label: 'Tài khoản', icon: 'user-round'),
    ],
  ),
];

/// Mục khớp dài nhất thắng, để `/review-history` không bị `/reviews` nuốt và
/// `/course-offerings/x` vẫn sáng mục Môn học.
String desktopActivePath(String path) {
  if (path == '/' || path.isEmpty) return '/dashboard';
  if (path.startsWith('/course-offerings')) return '/courses';
  if (path.startsWith('/review-schedule') ||
      path.startsWith('/group-questions')) {
    return '/dashboard';
  }
  _NavItem? best;
  for (final section in _sections) {
    for (final item in section.items) {
      final hit = path == item.path || path.startsWith('${item.path}/');
      if (hit && (best == null || item.path.length > best.path.length)) {
        best = item;
      }
    }
  }
  return best?.path ?? '';
}

String desktopTitle(String path) {
  final active = desktopActivePath(path);
  for (final section in _sections) {
    for (final item in section.items) {
      if (item.path == active) return item.label;
    }
  }
  return 'SRS Đánh giá AI';
}

/// Khung trang dùng chung cho mọi màn của giảng viên.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.path,
    required this.body,
    this.footer,
    this.showBackButton = false,
    super.key,
  });
  final String path;
  final Widget body;
  final Widget? footer;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    void open(String target) => AppNavigation.open(context, target);
    if (!AppLayout.isDesktop(context)) {
      return Scaffold(
        appBar: MobileHeader(
          onHome: () => open('/dashboard'),
          onBack: showBackButton ? () => open('/dashboard') : null,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?footer,
            AppBottomNavigation(path: path, onNavigate: open),
          ],
        ),
        body: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopSidebar(path: path),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopTopBar(path: path),
                Expanded(child: body),
                ?footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({required this.path, super.key});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final active = desktopActivePath(path);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed
          ? AppMetrics.sidebarCollapsedWidth
          : AppMetrics.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppMetrics.desktopTopBarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Row(
                children: [
                  if (!collapsed) ...[
                    const SizedBox(width: AppSpacing.s),
                    const AppIcon(
                      'files',
                      size: AppMetrics.iconLarge,
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: AppMetrics.gridGap),
                    Expanded(
                      child: Text(
                        'SRS Đánh giá AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.header,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  IconButton(
                    tooltip: collapsed ? 'Mở rộng menu' : 'Thu gọn menu',
                    onPressed: ref
                        .read(sidebarCollapsedProvider.notifier)
                        .toggle,
                    icon: AppIcon(
                      collapsed ? 'chevron-right' : 'chevron-left',
                      size: AppMetrics.iconSmall,
                    ),
                  ),
                  if (collapsed) const Spacer(),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.m,
              ),
              children: [
                for (final section in _sections) ...[
                  if (section.title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.m,
                        AppSpacing.l,
                        AppSpacing.m,
                        AppSpacing.s,
                      ),
                      child: collapsed
                          ? const Divider(height: 1, color: AppColors.line)
                          : Text(
                              section.title!,
                              style: AppTypography.badge.copyWith(
                                color: AppColors.muted,
                                fontSize: 11,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  for (final item in section.items)
                    _SidebarTile(
                      item: item,
                      selected: item.path == active,
                      collapsed: collapsed,
                      onTap: () =>
                          AppNavigation.openTopLevel(context, item.path),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final _NavItem item;
  final bool selected, collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brand : AppColors.ink;
    final tile = Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: selected ? AppColors.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            decoration: selected
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.brand, width: 3),
                    ),
                  )
                : null,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                AppIcon(
                  item.icon,
                  size: AppMetrics.iconSmall,
                  color: selected ? AppColors.brand : AppColors.muted,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: collapsed ? Tooltip(message: item.label, child: tile) : tile,
    );
  }
}

class DesktopTopBar extends ConsumerWidget {
  const DesktopTopBar({required this.path, super.key});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Có Firebase thì hiện đúng người đăng nhập; test không có Firebase thì
    // chỉ hiện nhãn vai trò, không bịa tên.
    final firebaseReady = ref.watch(firebaseInitializedProvider);
    final user = firebaseReady ? ref.watch(currentUserProvider).value : null;
    final name = (user?.displayName.trim().isNotEmpty ?? false)
        ? user!.displayName.trim()
        : (user?.email ?? 'Giảng viên');
    return Container(
      height: AppMetrics.desktopTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        spacing: AppSpacing.m,
        children: [
          Expanded(
            child: Text(
              desktopTitle(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.header,
            ),
          ),
          IconButton(
            tooltip: 'Thông báo',
            onPressed: () =>
                AppNavigation.openTopLevel(context, '/notifications'),
            icon: const AppIcon('inbox', color: AppColors.ink),
          ),
          if (user != null) AppBadge(user.roleLabel, tone: 'brand'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.strong,
            ),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => AppNavigation.openTopLevel(context, '/profile'),
            child: CircleAvatar(
              radius: AppMetrics.avatarRadius,
              backgroundColor: AppColors.brand,
              child: Text(
                user?.initials ?? 'GV',
                style: AppTypography.badge.copyWith(color: AppColors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
