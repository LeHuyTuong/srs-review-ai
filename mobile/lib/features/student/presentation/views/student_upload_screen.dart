import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/current_user_view_model.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/viewmodels/student_upload_view_model.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';

/// Lớp/dự án cho dropdown nộp bài và để hiện tên lớp ở "Bài của tôi".
final studentAcademicSnapshotProvider = StreamProvider<AcademicSnapshot>((ref) {
  return ref.watch(firestoreAcademicServiceProvider).watch();
});

/// Bước 1 của sinh viên: chọn lớp, dự án, tệp rồi nộp.
class StudentUploadPanel extends ConsumerWidget {
  const StudentUploadPanel({this.onViewMine, super.key});

  /// Mở tab "Bài của tôi" sau khi nộp xong.
  final VoidCallback? onViewMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(studentAcademicSnapshotProvider);
    final remoteConfig =
        ref.watch(remoteConfigValuesProvider).value ??
        const RemoteConfigValues();
    final state = ref.watch(studentUploadViewModelProvider);
    final vm = ref.read(studentUploadViewModelProvider.notifier);

    return snapshot.when(
      loading: () => const AppLoadingState(),
      error: (_, _) => AppErrorState(
        onRetry: () => ref.invalidate(studentAcademicSnapshotProvider),
      ),
      data: (data) {
        final classes = submittableClasses(
          data,
          ref.watch(currentUserProvider).value?.email,
        );
        final projects = state.classId == null
            ? const <AcademicRecord>[]
            : data.classProjects(state.classId!);
        final selectedClass = classes.any((c) => c.id == state.classId)
            ? state.classId
            : null;
        final selectedProject = projects.any((p) => p.id == state.projectId)
            ? state.projectId
            : null;
        final types = remoteConfig.allowedSrsFileTypes
            .map((t) => t.toUpperCase())
            .join(', ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.l,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Semantics(
                  header: true,
                  headingLevel: 1,
                  child: Text(
                    'Nộp tài liệu SRS',
                    style: AppTypography.pageHeading,
                  ),
                ),
                Text(
                  'Định dạng: $types · Tối đa ${remoteConfig.maxUploadFileSizeMb} MB.',
                  style: AppTypography.muted,
                ),
              ],
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.l,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('class-$selectedClass'),
                    initialValue: selectedClass,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Lớp',
                      border: OutlineInputBorder(),
                    ),
                    hint: Text(
                      classes.isEmpty ? 'Chưa có lớp nào' : 'Chọn lớp',
                    ),
                    items: [
                      for (final item in classes)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name.trim().isEmpty
                                ? item.code
                                : '${item.code} · ${item.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: state.uploading ? null : vm.selectClass,
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('project-$selectedClass-$selectedProject'),
                    initialValue: selectedProject,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dự án',
                      border: OutlineInputBorder(),
                    ),
                    hint: Text(
                      selectedClass == null
                          ? 'Chọn lớp trước'
                          : projects.isEmpty
                          ? 'Lớp này chưa có dự án'
                          : 'Chọn dự án',
                    ),
                    items: [
                      for (final item in projects)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: state.uploading ? null : vm.selectProject,
                  ),
                  _FilePickerTile(
                    fileName: state.file?.fileName,
                    sizeBytes: state.file?.sizeBytes,
                    onPick: state.uploading ? null : vm.pickFile,
                  ),
                  AppButton(
                    label: state.uploading ? 'Đang tải lên…' : 'Nộp tài liệu',
                    loading: state.uploading,
                    icon: const AppIcon(
                      'upload',
                      size: AppMetrics.iconSmall,
                      color: AppColors.white,
                    ),
                    onPressed: state.uploading || state.file == null
                        ? null
                        : vm.submit,
                  ),
                  if (state.uploading)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.xs,
                      children: [
                        LinearProgressIndicator(
                          value: state.progress > 0 ? state.progress : null,
                          color: AppColors.brand,
                          backgroundColor: AppColors.brandSoft,
                        ),
                        Text(
                          'Đã tải ${(state.progress * 100).round()}%',
                          style: AppTypography.muted,
                        ),
                      ],
                    ),
                  if (state.error case final error?)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: AppTypography.body.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (state.uploadedUrl case final url?)
              _SuccessCard(
                fileName: state.submittedFileName ?? '',
                url: url,
                onViewMine: onViewMine,
              ),
          ],
        );
      },
    );
  }
}

class _FilePickerTile extends StatelessWidget {
  const _FilePickerTile({
    required this.fileName,
    required this.sizeBytes,
    required this.onPick,
  });
  final String? fileName;
  final int? sizeBytes;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final picked = fileName != null;
    return Semantics(
      button: true,
      label: picked ? 'Đổi tệp, đang chọn $fileName' : 'Chọn tệp SRS',
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: picked ? AppColors.brandTint : AppColors.subtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: picked ? AppColors.brand : AppColors.line,
            ),
          ),
          child: Row(
            spacing: AppSpacing.m,
            children: [
              AppIcon(
                picked ? 'file-text' : 'file-up',
                color: picked ? AppColors.brand : AppColors.muted,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      fileName ?? 'Chọn tệp SRS',
                      style: AppTypography.strong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      picked
                          ? '${fileSizeLabel(sizeBytes ?? 0)} · bấm để đổi tệp'
                          : 'Bấm để chọn tệp từ máy',
                      style: AppTypography.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.fileName,
    required this.url,
    required this.onViewMine,
  });
  final String fileName;
  final Uri url;
  final VoidCallback? onViewMine;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: AppCard(
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.s,
        children: [
          Row(
            spacing: AppSpacing.s,
            children: [
              const AppIcon('circle-check', color: AppColors.brand),
              Expanded(
                child: Text('Đã nộp thành công', style: AppTypography.strong),
              ),
            ],
          ),
          Text(
            '$fileName đang chờ giảng viên. Theo dõi trạng thái ở mục Bài của tôi.',
            style: AppTypography.body,
          ),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              if (onViewMine != null)
                AppButton(
                  label: 'Xem Bài của tôi',
                  compact: true,
                  onPressed: onViewMine,
                ),
              AppButton(
                label: 'Sao chép link tệp',
                compact: true,
                variant: AppButtonVariant.secondary,
                icon: const AppIcon('copy', size: AppMetrics.iconSmall),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép link tệp')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
