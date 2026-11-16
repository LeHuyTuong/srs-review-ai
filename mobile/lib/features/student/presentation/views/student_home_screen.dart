import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/viewmodels/student_upload_view_model.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/my_submissions_view.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_inbox_view.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_upload_screen.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_scaffold.dart';

/// Ba mục của sinh viên. Giá trị là "path" giả để dùng chung DesktopSidebar.
abstract final class StudentTab {
  static const upload = 'upload';
  static const mine = 'mine';
  static const inbox = 'inbox';
  static const logout = 'logout';
  static const all = [upload, mine, inbox];
  static const labels = {
    upload: 'Nộp bài',
    mine: 'Bài của tôi',
    inbox: 'Thông báo',
  };
  static const icons = {upload: 'file-up', mine: 'files', inbox: 'inbox'};
}

final studentTabProvider = NotifierProvider<StudentTabState, String>(
  StudentTabState.new,
);

class StudentTabState extends Notifier<String> {
  @override
  String build() => StudentTab.upload;
  void select(String tab) => state = tab;
}

const _studentSections = <AppNavSection>[
  (
    title: null,
    items: [
      (path: StudentTab.upload, label: 'Nộp bài', icon: 'file-up'),
      (path: StudentTab.mine, label: 'Bài của tôi', icon: 'files'),
      (path: StudentTab.inbox, label: 'Thông báo', icon: 'inbox'),
    ],
  ),
  (
    title: 'TÀI KHOẢN',
    items: [(path: StudentTab.logout, label: 'Đăng xuất', icon: 'log-out')],
  ),
];

/// Khung của sinh viên: điện thoại = app bar + thanh tab dưới; màn rộng =
/// sidebar + top bar như màn giảng viên.
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(studentTabProvider);
    final unread = ref.watch(studentUnreadCountProvider);
    final uploading = ref.watch(
      studentUploadViewModelProvider.select((s) => s.uploading),
    );
    void select(String value) {
      if (value == StudentTab.logout) {
        if (!uploading) _logout(context, ref);
        return;
      }
      ref.read(studentTabProvider.notifier).select(value);
    }

    final body = _StudentBody(tab: tab, onSelect: select);

    if (!AppLayout.isDesktop(context)) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          surfaceTintColor: AppColors.white,
          // Tên trang đã là heading trong thân; app bar giữ tên ứng dụng.
          title: Text('SRS Đánh giá AI', style: AppTypography.header),
          actions: [
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: uploading ? null : () => _logout(context, ref),
              icon: const AppIcon('log-out', color: AppColors.ink),
            ),
          ],
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          backgroundColor: AppColors.white,
          indicatorColor: AppColors.brandSoft,
          selectedIndex: StudentTab.all.indexOf(tab),
          onDestinationSelected: (i) => select(StudentTab.all[i]),
          destinations: [
            for (final t in StudentTab.all)
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: t == StudentTab.inbox && unread > 0,
                  backgroundColor: AppColors.danger,
                  label: Text('$unread'),
                  child: AppIcon(StudentTab.icons[t]!),
                ),
                selectedIcon: AppIcon(
                  StudentTab.icons[t]!,
                  color: AppColors.brand,
                ),
                label: StudentTab.labels[t]!,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopSidebar(
            path: tab,
            sections: _studentSections,
            onSelect: select,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopTopBar(
                  path: tab,
                  fallbackName: 'Sinh viên',
                  inboxBadge: unread,
                  onInbox: () => select(StudentTab.inbox),
                  onProfile: () => select(StudentTab.mine),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentBody extends StatelessWidget {
  const _StudentBody({required this.tab, required this.onSelect});
  final String tab;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final desktop = AppLayout.isDesktop(context);
    final content = switch (tab) {
      StudentTab.mine => MySubmissionsView(
        onUpload: () => onSelect(StudentTab.upload),
      ),
      StudentTab.inbox => StudentInboxView(
        onOpenSubmissions: () => onSelect(StudentTab.mine),
      ),
      _ => StudentUploadPanel(onViewMine: () => onSelect(StudentTab.mine)),
    };
    final padding = AppLayout.pagePadding(context);
    return SingleChildScrollView(
      key: PageStorageKey('student-$tab'),
      padding: EdgeInsets.all(padding),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Biểu mẫu và danh sách đọc dễ hơn ở cột vừa phải, kể cả trên desktop.
          constraints: BoxConstraints(
            maxWidth: desktop
                ? AppMetrics.desktopContentWidth
                : AppMetrics.contentMaxWidth,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: KeyedSubtree(key: ValueKey(tab), child: content),
          ),
        ),
      ),
    );
  }
}

Future<void> _logout(BuildContext context, WidgetRef ref) async {
  final viewModel = ref.read(loginViewModelProvider);
  await viewModel.logout();
  if (!context.mounted ||
      viewModel.status != AuthStatus.error ||
      viewModel.errorMessage == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Không thể đăng xuất: ${viewModel.errorMessage}')),
  );
}

/// Giữ khoảng cách đều giữa các khối khi nhúng ở nơi khác.
const studentSectionGap = AppSpacing.l;
