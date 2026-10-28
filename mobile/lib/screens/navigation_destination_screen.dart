import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/widgets/mobile_header.dart';

// Điểm dừng điều hướng cho màn ngoài phạm vi; không giả lập nghiệp vụ đã hoàn thành.
class NavigationDestinationScreen extends StatelessWidget {
  const NavigationDestinationScreen({required this.path, super.key});
  final String path;

  String get title {
    if (path.startsWith('/reviews/')) return 'Yêu cầu đánh giá';
    if (path.startsWith('/projects/')) return 'Dự án';
    if (path.startsWith('/groups/')) return 'Nhóm';
    return {
          '/reviews': 'Đánh giá',
          '/projects': 'Dự án',
          '/notifications': 'Thông báo',
          '/profile': 'Tài khoản',
          '/project-registrations': 'Đăng ký dự án',
          '/classes': 'Lớp',
          '/groups': 'Nhóm',
          '/semesters': 'Học kỳ',
          '/courses': 'Môn học',
          '/students': 'Sinh viên',
          '/rule-sets': 'Bộ quy tắc',
        }[path] ??
        'Không tìm thấy trang';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: MobileHeader(
      onHome: () => AppNavigation.open(context, '/dashboard'),
    ),
    bottomNavigationBar: AppBottomNavigation(
      path: path,
      onNavigate: (target) => AppNavigation.open(context, target),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: AppEmptyState(
          title: title,
          description: 'Đường dẫn không tồn tại. Về tổng quan để tiếp tục.',
          action: AppButton(
            label: 'Về tổng quan',
            onPressed: () => AppNavigation.open(context, '/dashboard'),
          ),
        ),
      ),
    ),
  );
}
