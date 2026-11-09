import 'package:share_plus/share_plus.dart';

import 'package:srs_review_ai_mobile/features/academic/data/services/submission_file_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/submission_pdf_preview.dart';

typedef SubmissionLinkOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultSubmissionLinkOpener(Uri uri) async => false;

final submissionLinkOpenerProvider = Provider<SubmissionLinkOpener>(
  (ref) => _defaultSubmissionLinkOpener,
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
          : () => _openSubmission(context, ref, url, item.fileName),
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
            if (url != null)
              AppBadge(
                item.fileName.toLowerCase().endsWith('.pdf')
                    ? 'Xem PDF'
                    : 'Chia sẻ / lưu',
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSubmission(
  BuildContext context,
  WidgetRef ref,
  Uri url,
  String fileName,
) async {
  final customOpener = ref.read(submissionLinkOpenerProvider);
  if (!identical(customOpener, _defaultSubmissionLinkOpener)) {
    await customOpener(url);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    messenger.showSnackBar(const SnackBar(content: Text('Đang tải tệp…')));
    final bytes = await ref.read(submissionBytesFetcherProvider)(url);
    if (!context.mounted) return;
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SubmissionPdfPreview(bytes: bytes, fileName: fileName),
        ),
      );
      return;
    }
    if (!lowerName.endsWith('.docx') && !lowerName.endsWith('.md')) {
      throw const SubmissionFileException(
        'Định dạng tệp này chưa được hỗ trợ.',
      );
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: fileName,
            mimeType: lowerName.endsWith('.docx')
                ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                : 'text/markdown',
          ),
        ],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
    if (result.status == ShareResultStatus.dismissed) return;
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Không mở được tệp: $error')),
      );
    }
  }
}

String _formatTime(DateTime? at) {
  if (at == null) return 'vừa nộp';
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
}
