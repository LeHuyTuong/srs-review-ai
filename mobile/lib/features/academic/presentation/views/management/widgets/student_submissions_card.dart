import 'package:url_launcher/url_launcher.dart';

import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';

/// Mở link bài nộp; tách ra để test thay được.
typedef SubmissionLinkOpener = Future<bool> Function(Uri uri);

final submissionLinkOpenerProvider = Provider<SubmissionLinkOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Bài học viên nộp từ màn "Nộp tài liệu SRS". [projectId] rỗng = mọi dự án.
class StudentSubmissionsCard extends ConsumerWidget {
  const StudentSubmissionsCard({
    required this.snapshot,
    this.projectId = '',
    super.key,
  });

  final AcademicSnapshot snapshot;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentSubmissionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s,
      children: [
        Text('Bài nộp của học viên', style: AppTypography.strong),
        async.when(
          loading: () => const AppLoadingState(),
          error: (_, _) => AppErrorState(
            onRetry: () => ref.invalidate(studentSubmissionsProvider),
          ),
          data: (all) {
            final items = projectId.isEmpty
                ? all
                : all.where((s) => s.projectId == projectId).toList();
            if (items.isEmpty) {
              return const AppEmptyState(
                title: 'Chưa có bài nộp',
                description: 'Bài học viên nộp sẽ hiện ở đây ngay khi tải lên.',
              );
            }
            return AppCard(
              child: Column(
                children: [
                  for (final item in items) ...[
                    _SubmissionRow(item: item, snapshot: snapshot),
                    if (item != items.last)
                      const Divider(
                        height: AppMetrics.border,
                        color: AppColors.line,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SubmissionRow extends ConsumerWidget {
  const _SubmissionRow({required this.item, required this.snapshot});
  final StudentSubmission item;
  final AcademicSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = item.safeUrl;
    final project = item.projectId.isEmpty
        ? null
        : snapshot.project(item.projectId)?.name;
    final who = item.studentName.isNotEmpty ? item.studentName : 'Học viên';
    final meta = [who, ?project, _formatTime(item.uploadedAt)].join(' · ');
    return InkWell(
      onTap: url == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final opened = await ref.read(submissionLinkOpenerProvider)(url);
              if (!opened) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Không mở được tệp.')),
                );
              }
            },
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
                  Text(
                    item.fileName.isEmpty ? 'Tài liệu' : item.fileName,
                    style: AppTypography.strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    meta,
                    style: AppTypography.muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (url != null) const AppBadge('Mở tệp'),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime? at) {
  if (at == null) return 'vừa nộp';
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
}
