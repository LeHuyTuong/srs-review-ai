import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/document_card.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_filter_bar.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';

// Danh mục tài liệu theo cấu trúc dự án; chỉ hiện mục đã có bản nộp hoặc bản nháp.
class DocumentListScreen extends ConsumerWidget {
  const DocumentListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/documents',
    builder: (s) {
      ref.watch(managementListProvider('documents'));
      final vm = ref.read(managementListProvider('documents').notifier);
      return [
        const AppPageHeading(eyebrow: 'KHÔNG GIAN LÀM VIỆC', title: 'Tài liệu'),
        const ManagementFilterBar(
          kind: 'documents',
          noun: 'tài liệu',
          hint: 'Tìm tài liệu hoặc dự án...',
        ),
        AppCard(
          child: Column(
            children: [
              for (final d in vm.visible) ...[
                InkWell(
                  onTap: () => AppNavigation.open(
                    context,
                    d.text('reviewId').isEmpty
                        ? '/projects/${d.text('projectId')}/documents'
                        : '/reviews/${d.text('reviewId')}',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                    child: Row(
                      spacing: AppSpacing.m,
                      children: [
                        const AppIcon('file-text', size: AppMetrics.iconSmall),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: AppSpacing.xs,
                            children: [
                              Wrap(
                                spacing: AppSpacing.s,
                                runSpacing: AppSpacing.s,
                                children: [
                                  Text(
                                    d.text('title'),
                                    style: AppTypography.strong,
                                  ),
                                  if (d.text('latestVersion').isNotEmpty)
                                    AppBadge(d.text('latestVersion')),
                                ],
                              ),
                              Text(
                                '${vm.label(d.text('course'))} · ${vm.label(d.text('class'))} · ${vm.label(d.text('group'))} · ${s.project(d.text('projectId'))?.name ?? '—'}',
                                style: AppTypography.muted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: AppStatusBadge(d.text('status'), snapshot: s),
                        ),
                      ],
                    ),
                  ),
                ),
                if (d != vm.visible.last)
                  const Divider(
                    height: AppMetrics.border,
                    color: AppColors.line,
                  ),
              ],
              if (vm.visible.isEmpty)
                const AppEmptyState(title: 'Không có tài liệu phù hợp'),
            ],
          ),
        ),
      ];
    },
  );
}

// Danh sách tài liệu theo dự án với bốn phạm vi và thứ tự ưu tiên xử lý từ React.
class ProjectDocumentsScreen extends ConsumerWidget {
  const ProjectDocumentsScreen({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/projects/$projectId/documents',
    builder: (s) {
      final p = s.project(projectId);
      if (p == null) {
        return [const AppEmptyState(title: 'Không tìm thấy dự án')];
      }
      final key = 'documents:$projectId';
      final tab = ref.watch(managementListProvider(key)).tab;
      final vm = ref.read(managementListProvider(key).notifier);
      final projection = vm.projectDocuments(projectId);
      final visible = projection.visible;
      return [
        AcademicBackLink.to(label: p.name, fallback: '/projects/${p.id}'),
        const AppPageHeading(title: 'Tài liệu dự án'),
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.projectClass(p)?.code ?? '—'} · ${s.group(p.text('groupId'))?.name ?? '—'}',
                style: AppTypography.muted,
              ),
            ),
            AppStatusBadge(p.text('state'), snapshot: s),
          ],
        ),
        AppTabs(
          labels: [
            for (final (i, name) in const [
              'Tất cả',
              'Chờ đánh giá',
              'Cần chỉnh sửa',
              'Khóa gửi đánh giá',
            ].indexed)
              '$name (${projection.counts[i]})',
          ],
          selected: tab,
          onChanged: vm.tab,
          segmented: true,
        ),
        if (visible.isEmpty)
          const AppEmptyState(title: 'Không có tài liệu')
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final d in visible) ...[
                  ManagementDocumentCard(
                    document: d,
                    snapshot: s,
                    compact: true,
                  ),
                  if (d != visible.last)
                    const Divider(
                      height: AppMetrics.border,
                      color: AppColors.line,
                    ),
                ],
              ],
            ),
          ),
      ];
    },
  );
}
