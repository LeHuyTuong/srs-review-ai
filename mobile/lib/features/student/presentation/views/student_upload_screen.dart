import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/cloudinary_upload_service.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/student_file_picker_service.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';

final _studentAcademicSnapshotProvider = StreamProvider<AcademicSnapshot>((ref) {
  return ref.watch(firestoreAcademicServiceProvider).watch();
});

class StudentUploadScreen extends ConsumerStatefulWidget {
  const StudentUploadScreen({super.key});

  @override
  ConsumerState<StudentUploadScreen> createState() => _StudentUploadScreenState();
}

class _StudentUploadScreenState extends ConsumerState<StudentUploadScreen> {
  final _picker = const StudentFilePickerService();
  final _cloudinary = CloudinaryUploadService();
  PickedStudentSrsFile? _file;
  String? _classId;
  String? _projectId;
  bool _uploading = false;
  String? _error;
  Uri? _uploadedUrl;

  Future<void> _pickFile() async {
    setState(() { _error = null; _uploadedUrl = null; });
    try {
      final remoteConfig = ref.read(remoteConfigServiceProvider);
      await remoteConfig.initialize();
      final maxBytes = remoteConfig.values.maxUploadFileSizeMb * 1024 * 1024;
      final file = await _picker.pickSrsFile(
        maxSizeBytes: maxBytes,
        allowedExtensions: remoteConfig.values.allowedSrsFileTypes,
      );
      if (mounted && file != null) setState(() => _file = file);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _submit() async {
    final file = _file;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Vui lòng đăng nhập lại để nộp bài.');
      return;
    }
    if (file == null) {
      setState(() => _error = 'Vui lòng chọn tệp SRS trước.');
      return;
    }
    setState(() { _uploading = true; _error = null; _uploadedUrl = null; });
    try {
      final url = await _cloudinary.upload(
        bytes: file.bytes,
        fileName: file.fileName,
        folder: 'student-srs/${user.uid}',
      );
      final submission = FirebaseFirestore.instance.collection('submissions').doc();
      await submission.set({
        'file_url': url.toString(),
        'file_name': file.fileName,
        'uploaded_at': FieldValue.serverTimestamp(),
        'student_id': user.uid,
        if (_classId != null) 'class_id': _classId,
        if (_projectId != null) 'project_id': _projectId,
        'storage_provider': 'cloudinary',
      });
      if (mounted) setState(() => _uploadedUrl = url);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(_studentAcademicSnapshotProvider);
    final remoteConfig =
        ref.watch(remoteConfigValuesProvider).value ?? const RemoteConfigValues();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nộp tài liệu SRS'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: _uploading
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
        error: (error, _) => Center(child: Text('Không tải được danh sách lớp: $error')),
        data: (data) {
          final classes = data.classes;
          final projects = _classId == null ? const [] : data.classProjects(_classId!);
          final selectedClass = classes.any((item) => item.id == _classId) ? _classId : null;
          final selectedProject = projects.any((item) => item.id == _projectId) ? _projectId : null;
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
                decoration: const InputDecoration(labelText: 'Lớp', border: OutlineInputBorder()),
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
                onChanged: _uploading ? null : (value) => setState(() { _classId = value; _projectId = null; }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedProject,
                decoration: const InputDecoration(labelText: 'Dự án', border: OutlineInputBorder()),
                items: [for (final item in projects) DropdownMenuItem(value: item.id, child: Text(item.name))],
                onChanged: _uploading ? null : (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_file?.fileName ?? 'Chọn tệp SRS'),
              ),
              if (_file case final file?) ...[
                const SizedBox(height: 8),
                Text('${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB'),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _uploading ? null : _submit,
                icon: _uploading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_uploading ? 'Đang tải lên…' : 'Nộp tài liệu'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_uploadedUrl case final url?) ...[
                const SizedBox(height: 20),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Nộp tài liệu thành công', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(_file?.fileName ?? ''),
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
                                const SnackBar(content: Text('Đã sao chép link Cloudinary')),
                              );
                            }
                          },
                          icon: const Icon(Icons.content_copy),
                          label: const Text('Sao chép link'),
                        ),
                      ),
                    ]),
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
