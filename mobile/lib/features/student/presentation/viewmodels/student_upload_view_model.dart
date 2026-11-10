import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/student/data/my_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/cloudinary_upload_service.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/student_file_picker_service.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/submission_notifier.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';

final studentFilePickerServiceProvider = Provider<StudentFilePickerService>((
  ref,
) {
  return const StudentFilePickerService();
});

@immutable
class StudentUploadState {
  const StudentUploadState({
    this.file,
    this.classId,
    this.projectId,
    this.uploading = false,
    this.progress = 0.0,
    this.error,
    this.uploadedUrl,
  });

  final PickedStudentSrsFile? file;
  final String? classId;
  final String? projectId;
  final bool uploading;
  final double progress;
  final String? error;
  final Uri? uploadedUrl;

  StudentUploadState copyWith({
    PickedStudentSrsFile? file,
    String? classId,
    String? projectId,
    bool? uploading,
    double? progress,
    String? error,
    Uri? uploadedUrl,
    bool clearError = false,
    bool clearUploadedUrl = false,
    bool clearProjectId = false,
  }) => StudentUploadState(
    file: file ?? this.file,
    classId: classId ?? this.classId,
    projectId: clearProjectId ? null : (projectId ?? this.projectId),
    uploading: uploading ?? this.uploading,
    progress: progress ?? this.progress,
    error: clearError ? null : (error ?? this.error),
    uploadedUrl: clearUploadedUrl ? null : (uploadedUrl ?? this.uploadedUrl),
  );
}

class StudentUploadViewModel extends Notifier<StudentUploadState> {
  @override
  StudentUploadState build() => const StudentUploadState();

  void selectClass(String? classId) {
    state = state.copyWith(
      classId: classId,
      clearProjectId: true,
      clearError: true,
    );
  }

  void selectProject(String? projectId) {
    state = state.copyWith(projectId: projectId, clearError: true);
  }

  Future<void> pickFile() async {
    state = state.copyWith(
      clearError: true,
      clearUploadedUrl: true,
      progress: 0.0,
    );
    try {
      final remoteConfig = ref.read(remoteConfigServiceProvider);
      await remoteConfig.initialize();
      final maxBytes = remoteConfig.values.maxUploadFileSizeMb * 1024 * 1024;
      final picked = await ref
          .read(studentFilePickerServiceProvider)
          .pickSrsFile(
            maxSizeBytes: maxBytes,
            allowedExtensions: remoteConfig.values.allowedSrsFileTypes,
          );
      if (!ref.mounted) return;
      if (picked != null) {
        state = state.copyWith(file: picked, progress: 0.0, clearError: true);
      }
    } on Object catch (error, stackTrace) {
      unawaited(
        ref
            .read(crashlyticsServiceProvider)
            .logError(error, stackTrace, reason: 'student_pick_file_error'),
      );
      if (ref.mounted) {
        state = state.copyWith(error: error.toString());
      }
    }
  }

  /// Đọc bài đã nộp của chính sinh viên; lỗi đọc thì không chặn nộp bài.
  Future<String?> _duplicateOf(String uid, String hash) async {
    final repo = ref.read(mySubmissionsRepositoryProvider);
    if (repo == null) return null;
    try {
      final mine = await repo
          .watch(uid)
          .first
          .timeout(const Duration(seconds: 8));
      return duplicateUploadMessage(
        mine,
        projectId: state.projectId ?? '',
        hash: hash,
      );
    } on Object catch (error) {
      debugPrint('duplicate check skipped: $error');
      return null;
    }
  }

  Future<void> submit() async {
    final file = state.file;
    final user = ref.read(loginViewModelProvider).user;
    if (user == null) {
      state = state.copyWith(error: 'Vui lòng đăng nhập lại để nộp bài.');
      return;
    }
    if (file == null) {
      state = state.copyWith(error: 'Vui lòng chọn tệp SRS trước.');
      return;
    }

    state = state.copyWith(
      uploading: true,
      progress: 0.0,
      clearError: true,
      clearUploadedUrl: true,
    );

    final analytics = ref.read(analyticsServiceProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);

    try {
      final dot = file.fileName.lastIndexOf('.');
      final extension = dot < 0
          ? 'unknown'
          : file.fileName.substring(dot + 1).toLowerCase();

      // Tệp y hệt một bài đã nộp cho cùng dự án: báo ngay, không tải lên và
      // không tạo bài nộp mới (tránh chấm AI lại cùng nội dung).
      final hash = contentHashOf(file.bytes);
      final duplicate = await _duplicateOf(user.uid, hash);
      if (duplicate != null) {
        if (ref.mounted) {
          state = state.copyWith(uploading: false, error: duplicate);
        }
        return;
      }

      await analytics.logUploadSrsStart(
        fileType: extension,
        fileSizeBytes: file.bytes.length,
      );

      final url = await ref
          .read(cloudinaryUploadServiceProvider)
          .upload(
            bytes: file.bytes,
            fileName: file.fileName,
            folder: 'student-srs/${user.uid}',
            onProgress: (p) {
              if (ref.mounted) {
                state = state.copyWith(progress: p);
              }
            },
          );

      final firestore = ref.read(firestoreProvider);
      final submission = firestore.collection('submissions').doc();
      final now = FieldValue.serverTimestamp();
      final studentName = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : (user.email ?? '');

      await submission.set({
        'file_url': url.toString(),
        'file_name': file.fileName,
        'uploaded_at': now,
        'student_id': user.uid,
        'student_name': studentName,
        if (state.classId != null) 'class_id': state.classId,
        if (state.projectId != null) 'project_id': state.projectId,
        'storage_provider': 'cloudinary',
        'content_hash': hash,
      });

      // Đồng bộ sang `srs_reports` (kèm trường `uid` khớp firestore.rules) để Admin Web hiển thị trực tiếp
      unawaited(
        firestore
            .collection('srs_reports')
            .doc(submission.id)
            .set({
              'uid': user.uid,
              'fileName': file.fileName,
              'fileSize': file.bytes.length,
              'fileExtension': extension,
              'storagePath': 'student-srs/${user.uid}/${file.fileName}',
              'downloadUrl': url.toString(),
              'uploadedBy': user.uid,
              'uploadedByEmail': user.email ?? studentName,
              'uploadedAt': now,
              'status': 'pending',
              if (state.classId != null) 'classId': state.classId,
              if (state.projectId != null) 'projectId': state.projectId,
            })
            .catchError((Object e) {
              debugPrint('srs_reports mirror skipped: $e');
            }),
      );

      await analytics.logUploadSrsSuccess(documentId: submission.id);

      unawaited(
        ref.read(submissionNotifierProvider).notifyTeachers(submission.id),
      );

      if (ref.mounted) {
        state = state.copyWith(
          uploading: false,
          progress: 1.0,
          uploadedUrl: url,
        );
      }
    } on Object catch (error, stackTrace) {
      await crashlytics.logError(
        error,
        stackTrace,
        reason: 'student_upload_submit_error',
        keys: {
          'file_name': file.fileName,
          if (state.projectId != null) 'project_id': state.projectId!,
        },
      );
      if (ref.mounted) {
        state = state.copyWith(uploading: false, error: error.toString());
      }
    }
  }
}

final studentUploadViewModelProvider =
    NotifierProvider<StudentUploadViewModel, StudentUploadState>(
      StudentUploadViewModel.new,
    );
