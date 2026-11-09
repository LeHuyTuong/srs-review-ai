import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/viewmodels/student_upload_view_model.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';

final _studentAcademicSnapshotProvider = StreamProvider<AcademicSnapshot>((ref) {
  return ref.watch(firestoreAcademicServiceProvider).watch();
});

class StudentUploadScreen extends ConsumerWidget {
  const StudentUploadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(_studentAcademicSnapshotProvider);
    final remoteConfig =
        ref.watch(remoteConfigValuesProvider).value ?? const RemoteConfigValues();
    final uploadState = ref.watch(studentUploadViewModelProvider);
    final vm = ref.read(studentUploadViewModelProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nộp tài liệu SRS'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: uploadState.uploading
                ? null
                : () async {
                    final viewModel = ref.read(loginViewModelProvider);
                    await viewModel.logout();
                    if (!context.mounted ||
                        viewModel.status != AuthStatus.error ||
                        viewModel.errorMessage == null) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Không thể đăng xuất: ${viewModel.errorMessage}',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Không tải được danh sách lớp: $error')),
        data: (data) {
          final classes = data.classes;
          final projects = uploadState.classId == null
              ? const <AcademicRecord>[]
              : data.classProjects(uploadState.classId!);
          final selectedClass =
              classes.any((item) => item.id == uploadState.classId)
              ? uploadState.classId
              : null;
          final selectedProject =
              projects.any((item) => item.id == uploadState.projectId)
              ? uploadState.projectId
              : null;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Gửi tài liệu dự án', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Định dạng được phép: ${remoteConfig.allowedSrsFileTypes.map((type) => type.toUpperCase()).join(', ')} · Tối đa ${remoteConfig.maxUploadFileSizeMb} MB.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Lớp',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in classes)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        item.name.trim().isEmpty
                            ? item.code
                            : '${item.code} · ${item.name}',
                      ),
                    ),
                ],
                onChanged: uploadState.uploading ? null : vm.selectClass,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedProject,
                decoration: const InputDecoration(
                  labelText: 'Dự án',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in projects)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: uploadState.uploading ? null : vm.selectProject,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: uploadState.uploading ? null : vm.pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(uploadState.file?.fileName ?? 'Chọn tệp SRS'),
              ),
              if (uploadState.file case final file?) ...[
                const SizedBox(height: 8),
                Text(
                  '${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: uploadState.uploading ? null : vm.submit,
                icon: uploadState.uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  uploadState.uploading ? 'Đang tải lên…' : 'Nộp tài liệu',
                ),
              ),
              if (uploadState.uploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: uploadState.progress > 0 ? uploadState.progress : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tiến độ tải lên Cloudinary: ${(uploadState.progress * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (uploadState.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  uploadState.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (uploadState.uploadedUrl case final url?) ...[
                const SizedBox(height: 20),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nộp tài liệu thành công',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(uploadState.file?.fileName ?? ''),
                        const SizedBox(height: 6),
                        SelectableText(
                          'Link xem file: ${url.toString()}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: url.toString()),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã sao chép link Cloudinary'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.content_copy),
                            label: const Text('Sao chép link'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
