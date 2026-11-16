import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/group_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';

// Danh sách nhóm chia theo lớp đang hoạt động, dùng chung thẻ nhóm với chi tiết lớp.
class GroupListScreen extends StatelessWidget {
  const GroupListScreen({super.key});
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/groups',
    builder: (s) {
      final classes = GroupListPresentation(s).classes;
      return [
        const AppPageHeading(eyebrow: 'QUẢN LÝ', title: 'Nhóm sinh viên'),
        if (classes.isEmpty)
          const AppEmptyState(title: 'Chưa có lớp đang hoạt động'),
        for (final cls in classes)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Row(
                spacing: AppSpacing.s,
                children: [
                  Expanded(
                    child: Text(cls.code, style: AppTypography.ruleHeading),
                  ),
                  Text('${cls.groupCount} nhóm', style: AppTypography.muted),
                  AppButton(
                    label: 'Thêm nhóm',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => showAcademicForm(
                      context,
                      AcademicFormSpec('group', classId: cls.id),
                    ),
                  ),
                ],
              ),
              if (cls.groups.isEmpty)
                AppEmptyState(
                  title: 'Chưa có nhóm nào trong lớp này',
                  description:
                      'Tạo nhóm sinh viên đầu tiên cho lớp ${cls.code} để bắt đầu phân công đồ án.',
                  action: AppButton(
                    label: 'Tạo nhóm',
                    onPressed: () => showAcademicForm(
                      context,
                      AcademicFormSpec('group', classId: cls.id),
                    ),
                  ),
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final g in cls.groups) ...[
                        GroupSummaryCard(group: g, snapshot: s, compact: true),
                        if (g != cls.groups.last)
                          const Divider(
                            height: AppMetrics.border,
                            color: AppColors.line,
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
      ];
    },
  );
}

// Màn quản trị nhóm gửi lệnh đến ViewModel; thành viên và lịch sử được giữ nhất quán trong kho chung.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({required this.groupId, super.key});
  final String groupId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/groups/$groupId',
    builder: (s) {
      final g = s.group(groupId);
      if (g == null) return [const AppEmptyState(title: 'Không tìm thấy nhóm')];
      final presentation = GroupPresentationViewModel.detail(s, g);
      final cls = presentation.classRoom;
      final p = presentation.project;
      final limit = presentation.memberLimit;
      final members = presentation.members;
      final vm = ref.read(academicViewModelProvider.notifier);
      final readOnly = presentation.readOnly;
      final health = presentation.health;
      return [
        AcademicBackLink.to(
          label: cls?.code ?? 'Nhóm',
          fallback: '/classes/${g.classId}',
        ),
        AppPageHeading(
          eyebrow: 'QUẢN LÝ NHÓM · ${cls?.code ?? '—'}',
          title: g.name,
          aside: !presentation.canRename
              ? null
              : AppMoreMenu(
                  actions: {
                    'Đổi tên nhóm': () => showManagementForm(
                      context,
                      AcademicFormSpec('renameGroup', data: g.toJson()),
                    ),
                    if (presentation.canDelete)
                      'Xóa nhóm': () async {
                        if (await appConfirm(
                              context,
                              'Xóa nhóm',
                              'Nhóm chưa có thành viên và chưa có lịch sử đánh giá.',
                            ) &&
                            context.mounted) {
                          await academicAction(context, () async {
                            await vm.deleteGroup(g.id);
                            if (context.mounted) {
                              AppNavigation.open(
                                context,
                                '/classes/${g.classId}',
                              );
                            }
                          });
                        }
                      },
                  },
                ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s,
                children: [
                  Expanded(
                    child: Text(
                      '${presentation.memberCount}/$limit thành viên · Hoạt động ${presentation.activity}',
                      style: AppTypography.muted,
                    ),
                  ),
                  SizedBox(
                    width: AppMetrics.groupHealthWidth,
                    child: AppBadge(
                      health?['label']?.toString() ?? '',
                      tone: health?['tone']?.toString() ?? 'neutral',
                    ),
                  ),
                ],
              ),
              AcademicProgress(
                value: g.integer('progress'),
                label: 'Tiến độ nhóm (ghi nhận)',
              ),
              Text(
                'Chờ đánh giá: ${g.integer('pendingReviews')} tài liệu',
                style: AppTypography.muted,
              ),
            ],
          ),
        ),
        if (readOnly)
          const AppNotice('Lớp đã lưu trữ. Thông tin nhóm chỉ được xem.'),
        if (presentation.overCapacity)
          Text(
            'Nhóm có ${presentation.memberCount}/$limit thành viên. Giữ nguyên thành viên; không thể thêm người mới.',
            style: AppTypography.body.copyWith(color: AppColors.amber),
          ),
        Text('Dự án', style: AppTypography.ruleHeading),
        AppCard(
          tinted: p != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Text(
                p?.name ?? 'Nhóm chưa được gán dự án.',
                style: p != null
                    ? AppTypography.blockTitle
                    : AppTypography.muted,
              ),
              if (p != null) ...[
                Text(p.text('description'), style: AppTypography.muted),
                AppButton(
                  label: 'Xem dự án',
                  variant: AppButtonVariant.secondary,
                  onPressed: () =>
                      AppNavigation.open(context, '/projects/${p.id}'),
                ),
              ] else
                Row(
                  spacing: AppSpacing.s,
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Gán dự án',
                        variant: AppButtonVariant.secondary,
                        onPressed: presentation.canAssignProject
                            ? () => showManagementForm(
                                context,
                                AcademicFormSpec(
                                  'assignProject',
                                  data: g.toJson(),
                                ),
                              )
                            : null,
                      ),
                    ),
                    Expanded(
                      child: AppButton(
                        label: 'Tạo dự án',
                        onPressed: !presentation.canCreateProject
                            ? null
                            : () => showManagementForm(
                                context,
                                AcademicFormSpec('project', classId: g.id),
                              ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text('Thành viên', style: AppTypography.ruleHeading),
            ),
            Text(
              '${presentation.memberCount}/$limit thành viên',
              style: AppTypography.muted,
            ),
          ],
        ),
        if (members.isEmpty)
          const AppEmptyState(title: 'Nhóm chưa có thành viên')
        else
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < members.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                    child: Row(
                      spacing: AppSpacing.m,
                      children: [
                        CircleAvatar(
                          radius: AppMetrics.avatarRadius,
                          backgroundColor: AppColors.brandSoft,
                          child: Text(
                            members[i].text('initials'),
                            style: AppTypography.strong,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                members[i].name,
                                style: AppTypography.strong,
                              ),
                              Text(
                                '${members[i].studentCode}${i == 0 ? ' · Trưởng nhóm' : ''}',
                                style: AppTypography.muted,
                              ),
                            ],
                          ),
                        ),
                        if (presentation.canRemoveMember)
                          TextButton(
                            onPressed: () async {
                              if (await appConfirm(
                                    context,
                                    'Xóa khỏi nhóm',
                                    '${members[i].name} sẽ được chuyển về danh sách chưa có nhóm. Tài liệu, phiên bản và lịch sử đánh giá vẫn được giữ nguyên.',
                                  ) &&
                                  context.mounted) {
                                await academicAction(
                                  context,
                                  () => vm.removeMember(g.id, members[i].id),
                                );
                              }
                            },
                            child: const Text('Xóa khỏi nhóm'),
                          ),
                      ],
                    ),
                  ),
                  if (i < members.length - 1)
                    const Divider(
                      height: AppMetrics.border,
                      color: AppColors.line,
                    ),
                ],
              ],
            ),
          ),
        AppButton(
          label: 'Thêm thành viên',
          variant: AppButtonVariant.secondary,
          icon: const AppIcon('users'),
          onPressed: !presentation.canAddMember
              ? null
              : () => showManagementForm(
                  context,
                  AcademicFormSpec('member', data: g.toJson()),
                ),
        ),
        const AppNotice(
          'Xóa sinh viên khỏi nhóm không xóa tài liệu hay lịch sử đánh giá mà sinh viên đó đã nộp.',
        ),
      ];
    },
  );
}
