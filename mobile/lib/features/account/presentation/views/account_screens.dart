import 'package:srs_review_ai_mobile/theme/app_feature_metrics.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/notification_view_model.dart';

// Hiển thị hồ sơ từ dữ liệu mẫu và gửi thao tác đăng xuất tới ViewModel quản lý phiên.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/profile',
    builder: (s) {
      final user = AcademicRecord(
        Map<String, dynamic>.from(s.data['currentUser'] as Map),
      );
      return [
        const AppPageHeading(title: 'Tài khoản', eyebrow: 'TÀI KHOẢN'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Row(
                spacing: AppSpacing.m,
                children: [
                  CircleAvatar(
                    radius: AppFeatureMetrics.profileAvatarRadius,
                    child: Text(user.text('initials')),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: AppTypography.header),
                        Text(
                          user.text('email'),
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  AppBadge(user.text('role'), tone: 'brand'),
                  AppBadge(user.text('semester')),
                ],
              ),
              AppMetaGrid(
                items: [
                  ('Lớp phụ trách', '${s.classes.length} lớp'),
                  ('Sinh viên', '${s.students.length} sinh viên'),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.s,
          children: [
            Text('QUẢN LÝ HỌC VỤ', style: AppTypography.strong),
            Text(
              'Lối tắt truy cập các danh mục dữ liệu đào tạo',
              style: AppTypography.muted,
            ),
          ],
        ),
        AppCard(
          child: Column(
            children: [
              for (final item in [
                (
                  'Học kỳ',
                  '${s.semesters.length} học kỳ',
                  '/semesters',
                  'calendar',
                ),
                (
                  'Môn học & Đợt học',
                  '${s.courses.length} môn',
                  '/courses',
                  'book-open',
                ),
                ('Lớp học', '${s.classes.length} lớp', '/classes', 'school'),
                (
                  'Sinh viên',
                  '${s.students.length} sinh viên',
                  '/students',
                  'graduation-cap',
                ),
                (
                  'Nhóm sinh viên',
                  '${s.groups.length} nhóm',
                  '/groups',
                  'users',
                ),
              ])
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AppIcon(item.$4, color: AppColors.brand),
                    title: Text(item.$1),
                    subtitle: Text(item.$2),
                    trailing: const AppIcon('chevron-right'),
                    onTap: () => AppNavigation.open(context, item.$3),
                  ),
                ),
            ],
          ),
        ),
        AppButton(
          label: 'Đăng xuất',
          variant: AppButtonVariant.danger,
          icon: const AppIcon('log-out'),
          onPressed: () => ref.read(sessionProvider.notifier).signOut(),
        ),
      ];
    },
  );
}

// Hiển thị thông báo theo thẻ; lỗi tải có thao tác thử lại qua provider.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsState();
}

class _NotificationsState extends ConsumerState<NotificationsScreen> {
  int get tab => ref.watch(notificationTabProvider);
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/notifications',
    builder: (_) => ref
        .watch(notificationScreenProvider)
        .when(
          loading: () => [const AppLoadingState()],
          error: (e, stack) => [
            AppErrorState(
              onRetry: () => ref.read(notificationTabProvider.notifier).retry(),
            ),
          ],
          data: (view) {
            return [
              AppPageHeading(
                title: 'Thông báo',
                eyebrow: 'CẬP NHẬT',
                description: '${view.unread} thông báo chưa đọc',
              ),
              AppTabs(
                labels: const [
                  'Tất cả',
                  'Chưa đọc',
                  'Đánh giá',
                  'Hạn nộp',
                  'Đánh giá AI',
                ],
                selected: tab,
                onChanged: (i) =>
                    ref.read(notificationTabProvider.notifier).select(i),
                segmented: true,
              ),
              if (view.isEmpty) AppEmptyState(title: view.emptyTitle),
              for (final section in view.sections) ...[
                Text(section, style: AppTypography.sectionHeading),
                for (final n in view.sectionItems(section))
                  AppCard(
                    tinted: n.flag('unread'),
                    child: InkWell(
                      onTap: () => AppNavigation.open(
                        context,
                        n.text('link', '/dashboard'),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.m,
                        children: [
                          AppIcon(n.text('kind'), color: AppColors.brand),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: AppSpacing.s,
                              children: [
                                Text(
                                  AcademicPresentation.content(n.text('title')),
                                  style: n.flag('unread')
                                      ? AppTypography.strong
                                      : AppTypography.body,
                                ),
                                Text(
                                  AcademicPresentation.content(n.text('meta')),
                                  style: AppTypography.muted,
                                ),
                                Text(
                                  'Xem chi tiết →',
                                  style: AppTypography.strong.copyWith(
                                    color: AppColors.brand,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ];
          },
        ),
  );
}
