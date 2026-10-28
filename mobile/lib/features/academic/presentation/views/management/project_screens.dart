import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_form_sheet.dart';
export 'package:srs_review_ai_mobile/features/academic/presentation/views/management/project_registrations_screen.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_filter_bar.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/document_card.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';

// Danh sách dự án có phạm vi học kỳ/trạng thái giống ProjectListPage.
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/projects',
    builder: (s) {
      ref.watch(managementListProvider('projects'));
      final vm = ref.read(managementListProvider('projects').notifier);
      return [
        const AppPageHeading(eyebrow: 'QUẢN LÝ DỰ ÁN', title: 'Dự án'),
        AppButton(
          label: 'Tạo dự án',
          icon: const AppIcon('plus'),
          onPressed: () =>
              showManagementForm(context, const AcademicFormSpec('project')),
        ),
        const ManagementFilterBar(
          kind: 'projects',
          noun: 'dự án',
          hint: 'Tìm dự án hoặc nhóm...',
        ),
        for (final p in vm.visible)
          InkWell(
            onTap: () => AppNavigation.open(context, '/projects/${p.id}'),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.m,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.s,
                    runSpacing: AppSpacing.s,
                    children: [
                      Text(
                        '${s.course(s.projectClass(p)?.courseId ?? '')?.code ?? '—'} · ${s.projectClass(p)?.code ?? '—'} · ${s.group(p.text('groupId'))?.name ?? '—'}',
                        style: AppTypography.muted,
                      ),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          AppStatusBadge(p.text('state'), snapshot: s),
                          if (p.text('state') == 'active' &&
                              s.group(p.text('groupId')) != null)
                            AppBadge(
                              ((s.data['groupHealthMeta'] as Map)[s
                                          .group(p.text('groupId'))!
                                          .text('health')]
                                      as Map)['label']
                                  .toString(),
                              tone:
                                  ((s.data['groupHealthMeta'] as Map)[s
                                              .group(p.text('groupId'))!
                                              .text('health')]
                                          as Map)['tone']
                                      .toString(),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Text(p.name, style: AppTypography.header),
                  AcademicProgress(
                    value: p.integer('progress'),
                    label: 'Tiến độ dự án (ghi nhận)',
                  ),
                  Text(
                    'Hạn nộp ${AcademicPresentation.date(p.text('deadline'))}',
                    style: AppTypography.muted,
                  ),
                ],
              ),
            ),
          ),
        if (vm.visible.isEmpty)
          AppEmptyState(
            title: 'Chưa có dự án phù hợp',
            description: 'Chọn trạng thái khác hoặc xóa bộ lọc.',
            action: AppButton(
              label: 'Xóa bộ lọc',
              variant: AppButtonVariant.secondary,
              onPressed: vm.clear,
            ),
          ),
      ];
    },
  );
}

// Chi tiết dự án với năm tab thật, không tạo bản sao dữ liệu nhóm hoặc tài liệu.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/projects/$projectId',
    builder: (s) {
      final p = s.project(projectId);
      if (p == null) {
        return [const AppEmptyState(title: 'Không tìm thấy dự án')];
      }
      final cls = s.projectClass(p);
      final g = s.group(p.text('groupId'));
      final off = s.offering(cls?.offeringId ?? '');
      final docs = s.projectDocuments(p);
      final archived = p.text('state') == 'archived';
      // Dự án lưu trữ hoặc lớp không còn hoạt động chỉ cho xem; lớp phải hoạt động mới được khôi phục dự án.
      final readOnly = AcademicPresentationViewModel(s).projectReadOnly(p, cls);
      final key = 'project:$projectId';
      final state = ref.watch(managementListProvider(key));
      final tabs = ref.read(managementListProvider(key).notifier);
      final vm = ref.read(academicViewModelProvider.notifier);
      final reviews = AcademicPresentationViewModel(s).projectReviews(p.id);
      final events = AcademicPresentationViewModel(s).projectEvents(reviews);
      return [
        AcademicBackLink.to(
          label: '${cls?.code ?? '—'} / ${g?.name ?? '—'}',
          fallback: cls == null ? '/projects' : '/classes/${cls.id}',
        ),
        AppPageHeading(
          eyebrow: '${cls?.code ?? '—'} · ${g?.name ?? '—'}',
          title: p.name,
          aside: AppMoreMenu(
            actions: {
              if (!readOnly)
                'Chỉnh sửa thông tin': () => showManagementForm(
                  context,
                  AcademicFormSpec('project', data: p.toJson()),
                ),
              if (cls?.archived == false)
                archived ? 'Khôi phục dự án' : 'Lưu trữ dự án': () async {
                  if (archived ||
                      await appConfirm(
                        context,
                        'Lưu trữ dự án',
                        'Dự án chuyển sang chỉ đọc. Tài liệu, phiên bản và lịch sử đánh giá vẫn được giữ nguyên.',
                      )) {
                    if (context.mounted) {
                      await academicAction(
                        context,
                        () => vm.setProjectState(
                          p.id,
                          archived ? 'active' : 'archived',
                        ),
                      );
                    }
                  }
                },
              if (!s.hasProjectHistory(p.id) && cls?.archived == false)
                'Xóa dự án': () async {
                  if (await appConfirm(
                        context,
                        'Xóa dự án',
                        'Chỉ xóa dự án chưa có tài liệu và lịch sử đánh giá.',
                      ) &&
                      context.mounted) {
                    await academicAction(context, () async {
                      await vm.deleteProject(p.id);
                      if (context.mounted) {
                        AppNavigation.open(context, '/projects');
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
                children: [
                  AppStatusBadge(p.text('state'), snapshot: s),
                  const Spacer(),
                  const AppIcon('calendar-clock'),
                ],
              ),
              AcademicProgress(
                value: p.integer('progress'),
                label: 'Tiến độ dự án (ghi nhận)',
              ),
              Text(
                'Tài liệu được duyệt: ${AcademicPresentationViewModel(s).approvedDocumentCount(docs)}/${docs.length}',
                style: AppTypography.muted,
              ),
            ],
          ),
        ),
        if (archived)
          const AppNotice(
            'Dự án đã được lưu trữ. Toàn bộ tài liệu, phiên bản và lịch sử đánh giá vẫn được giữ nguyên ở chế độ chỉ đọc.',
          ),
        AppButton(
          label: 'Mở tài liệu',
          onPressed: () =>
              AppNavigation.open(context, '/projects/${p.id}/documents'),
        ),
        AppTabs(
          labels: const [
            'Tổng quan',
            'Tài liệu',
            'Thành viên',
            'Lịch sử đánh giá',
            'Thông tin',
          ],
          selected: state.tab,
          onChanged: tabs.tab,
          segmented: true,
        ),
        if (state.tab == 0) ...[
          if (s.projectNextStep(p).isNotEmpty)
            AppNotice(AcademicPresentation.content(s.projectNextStep(p))),
          Text('Tiến độ tài liệu', style: AppTypography.ruleHeading),
          AppCard(
            child: Column(
              children: [
                for (final d in docs) ...[
                  ManagementDocumentCard(
                    document: d,
                    snapshot: s,
                    roadmap: true,
                  ),
                  if (d != docs.last)
                    const Divider(
                      height: AppMetrics.border,
                      color: AppColors.line,
                    ),
                ],
              ],
            ),
          ),
          if (AcademicPresentationViewModel(s).hasLockedDraft(docs))
            const AppNotice(
              'Có tài liệu đang khóa gửi đánh giá. Cần phê duyệt các tài liệu phụ thuộc trước.',
            ),
        ],
        if (state.tab == 1) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tài liệu (${docs.length})',
                  style: AppTypography.ruleHeading,
                ),
              ),
              TextButton(
                onPressed: () =>
                    AppNavigation.open(context, '/projects/${p.id}/documents'),
                child: const Text('Mở trang tài liệu'),
              ),
            ],
          ),
          for (final d in docs)
            ManagementDocumentCard(document: d, snapshot: s),
          if (docs.isEmpty) const AppEmptyState(title: 'Chưa có tài liệu'),
        ],
        if (state.tab == 2) ...[
          Text('Thành viên nhóm', style: AppTypography.ruleHeading),
          if (p.values('members').isEmpty)
            const AppEmptyState(title: 'Chưa có thành viên'),
          for (final row in p.values('members'))
            _ProjectMember(member: AcademicRecord(row as AcademicJson)),
          if (g != null)
            AppButton(
              label: 'Quản lý thành viên tại nhóm',
              variant: AppButtonVariant.secondary,
              onPressed: () => AppNavigation.open(context, '/groups/${g.id}'),
            ),
        ],
        if (state.tab == 3) ...[
          for (final r in reviews)
            TextButton(
              onPressed: () =>
                  AppNavigation.open(context, '/reviews/${r.id}/history'),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${r.text('documentTitle')} ${r.text('version')} →',
                ),
              ),
            ),
          ReviewTimeline(events: events),
          if (events.isEmpty)
            const AppEmptyState(title: 'Chưa có hoạt động đánh giá'),
        ],
        if (state.tab == 4) ...[
          Text(p.text('description')),
          AppMetaGrid(
            items: [
              ('Học kỳ', s.semester(cls?.semesterId ?? '')?.name ?? '—'),
              ('Môn học', s.course(cls?.courseId ?? '')?.name ?? '—'),
              ('Lớp', cls?.code ?? '—'),
              ('Nhóm', g?.name ?? '—'),
              ('Giảng viên', p.text('lecturer')),
              (
                'Phương pháp dạy',
                p.text(
                  'teachingMethodOverride',
                  cls?.methodOverride.isNotEmpty == true
                      ? cls!.methodOverride
                      : off?.teachingMethod ?? '—',
                ),
              ),
              ('Ngày bắt đầu', AcademicPresentation.date(p.text('startDate'))),
              ('Hạn nộp', AcademicPresentation.date(p.text('deadline'))),
              if (p.text('reviewCutoff').isNotEmpty)
                (
                  'Hạn nhận đánh giá',
                  AcademicPresentation.date(p.text('reviewCutoff'), time: true),
                ),
            ],
          ),
          if (cls != null)
            TextButton(
              onPressed: () => AppNavigation.open(
                context,
                '/rule-sets#${s.effectiveRule(cls)?.id ?? ''}',
              ),
              child: Text(
                'Bộ quy tắc: ${s.effectiveRule(cls)?.name ?? 'Chưa gán'} →',
              ),
            ),
          if (!readOnly)
            AppButton(
              label: 'Chỉnh sửa thông tin',
              variant: AppButtonVariant.secondary,
              onPressed: () => showManagementForm(
                context,
                AcademicFormSpec('project', data: p.toJson()),
              ),
            ),
        ],
      ];
    },
  );
}

class _ProjectMember extends StatelessWidget {
  const _ProjectMember({required this.member});
  final AcademicRecord member;
  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.m,
    children: [
      CircleAvatar(
        radius: AppMetrics.avatarRadius,
        backgroundColor: AppColors.brandSoft,
        child: Text(member.text('initials'), style: AppTypography.strong),
      ),
      Expanded(child: Text(member.name, style: AppTypography.strong)),
      Text(member.text('role'), style: AppTypography.muted),
    ],
  );
}
