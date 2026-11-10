import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Ba bước sinh viên thấy được. Chỉ suy từ field giảng viên/server đã ghi lên
/// `submissions/{id}`, không đoán theo thời gian.
enum SubmissionStage { submitted, reviewing, done }

/// Một bài nộp của chính sinh viên đang đăng nhập.
class MySubmission {
  const MySubmission({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    this.classId = '',
    this.projectId = '',
    this.uploadedAt,
    this.status = '',
    this.decision = '',
    this.decisionReason = '',
    this.decidedAt,
    this.contentHash = '',
  });

  factory MySubmission.fromJson(String id, Map<String, dynamic> data) =>
      MySubmission(
        id: id,
        fileName: data['file_name'] as String? ?? '',
        fileUrl: data['file_url'] as String? ?? '',
        classId: data['class_id'] as String? ?? '',
        projectId: data['project_id'] as String? ?? '',
        uploadedAt: _time(data['uploaded_at']),
        status: data['status'] as String? ?? '',
        decision: data['decision'] as String? ?? '',
        decisionReason: data['decision_reason'] as String? ?? '',
        decidedAt: _time(data['decided_at']),
        contentHash: data['content_hash'] as String? ?? '',
      );

  final String id, fileName, fileUrl, classId, projectId;
  final String status, decision, decisionReason;

  /// sha256 nội dung tệp; rỗng với bài nộp trước khi có tính năng này.
  final String contentHash;

  /// `null` khi server timestamp chưa về (vừa nộp trên chính máy này).
  final DateTime? uploadedAt, decidedAt;

  static const decisions = {'approved', 'needsRevision', 'notAccepted'};

  /// Có quyết định hợp lệ là xong, kể cả khi `status` chưa kịp ghi (server
  /// ghi `decision` bằng Admin SDK, không đụng `status`).
  SubmissionStage get stage {
    if (decisions.contains(decision) || status == 'reviewed') {
      return SubmissionStage.done;
    }
    if (status == 'reviewing') return SubmissionStage.reviewing;
    return SubmissionStage.submitted;
  }

  /// Nhãn trạng thái ngắn cho badge.
  String get stageLabel => switch (stage) {
    SubmissionStage.submitted =>
      status == 'queued' ? 'Đã vào hàng chờ' : 'Đã nộp',
    SubmissionStage.reviewing => 'Đang chấm',
    SubmissionStage.done => decisionLabel ?? 'Đã có kết quả',
  };

  String? get decisionLabel => switch (decision) {
    'approved' => 'Đạt',
    'needsRevision' => 'Cần chỉnh sửa',
    'notAccepted' => 'Không đạt',
    _ => null,
  };

  /// Tone của `AppBadge`.
  String get tone => switch (stage) {
    SubmissionStage.submitted => 'neutral',
    SubmissionStage.reviewing => 'amber',
    SubmissionStage.done => switch (decision) {
      'approved' => 'brand',
      'needsRevision' => 'rust',
      'notAccepted' => 'danger',
      _ => 'olive',
    },
  };

  /// Chỉ mở link Cloudinary https; giá trị khác coi như không có link.
  Uri? get safeUrl {
    final uri = Uri.tryParse(fileUrl);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'res.cloudinary.com'
        ? uri
        : null;
  }

  static DateTime? _time(Object? value) => switch (value) {
    Timestamp t => t.toDate(),
    DateTime d => d,
    _ => null,
  };
}

/// sha256 (hex) của nội dung tệp, dùng để nhận ra tệp nộp lại y hệt.
String contentHashOf(Uint8List bytes) => sha256.convert(bytes).toString();

/// Lời báo khi tệp sắp nộp trùng nội dung một bài đã nộp cho cùng dự án;
/// `null` nếu không trùng. Bài cũ chưa có hash không bao giờ bị coi là trùng.
String? duplicateUploadMessage(
  List<MySubmission> mine, {
  required String projectId,
  required String hash,
}) {
  if (hash.isEmpty) return null;
  final same = mine
      .where((m) => m.projectId == projectId && m.contentHash == hash)
      .firstOrNull;
  if (same == null) return null;
  final t = same.uploadedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  final when = t == null
      ? ''
      : ' lúc ${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  return 'File giống hệt bài "${same.fileName}" bạn đã nộp$when. '
      'Hãy sửa tài liệu trước khi nộp lại.';
}
