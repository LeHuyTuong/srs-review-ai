import 'package:flutter/material.dart';

import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_radius.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';

// Năm điểm đến theo nguồn React; selected được xác định bằng đường dẫn hiện tại.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.path,
    required this.onNavigate,
    super.key,
  });
  final String path;
  final ValueChanged<String> onNavigate;
  static const destinations = [
    (path: '/dashboard', label: 'Tổng quan', icon: 'layout-dashboard'),
    (path: '/projects', label: 'Dự án', icon: 'folder'),
    (path: '/reviews', label: 'Đánh giá', icon: 'file-check-2'),
    (path: '/notifications', label: 'Thông báo', icon: 'inbox'),
    (path: '/profile', label: 'Tài khoản', icon: 'user-round'),
  ];

  static String activePath(String path) {
    if ([
      '/classes',
      '/groups',
      '/semesters',
      '/documents',
      '/rule-sets',
      '/courses',
    ].any(path.startsWith)) {
      return '/projects';
    }
    if (path.startsWith('/review-history')) return '/reviews';
    // Không chọn mục nào nếu đường dẫn chưa thuộc nhóm điều hướng, như trang đợt môn học.
    return destinations
            .where((d) => path.startsWith(d.path))
            .firstOrNull
            ?.path ??
        '';
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(
        top: BorderSide(color: AppColors.line, width: AppMetrics.border),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s,
          AppMetrics.statGap + AppMetrics.border,
          AppSpacing.s,
          AppMetrics.statGap,
        ),
        child: Row(
          spacing: AppMetrics.navGap,
          children: [
            for (final item in destinations)
              Expanded(
                child: Semantics(
                  selected: activePath(path) == item.path,
                  button: true,
                  child: Material(
                    color: activePath(path) == item.path
                        ? AppColors.brandSoft
                        : AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      onTap: () => onNavigate(item.path),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSpacing.tapMin,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppMetrics.border,
                            vertical: AppSpacing.xs,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                item.icon,
                                color: activePath(path) == item.path
                                    ? AppColors.brand
                                    : AppColors.muted,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              // Độ rộng chữ Inter trên Flutter khác bản web một chút;
                              // co nhẹ nhãn khi thiếu chỗ để giữ đủ chữ như ảnh React.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  style: AppTypography.navigation.copyWith(
                                    color: activePath(path) == item.path
                                        ? AppColors.brand
                                        : AppColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
