/// Model đại diện cho báo cáo SRS đã được upload
class SrsReport {
  const SrsReport({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.uploadedBy,
    this.uploaderEmail = '',
    this.uploaderUid = '',
    required this.uploadDate,
    required this.status,
    required this.storagePath,
    this.downloadUrl = '',
  });

  final String id;
  final String fileName;
  final int fileSize; // bytes
  final String uploadedBy;
  final String uploaderEmail;
  final String uploaderUid;
  final DateTime uploadDate;
  final String status; // 'pending', 'reviewed', 'approved', 'rejected'
  final String storagePath;
  final String downloadUrl;

  /// Họ tên hiển thị chuẩn hoá ở dòng 1
  String get uploaderDisplayName {
    final raw = uploadedBy.trim();
    if (raw.contains('@')) {
      final prefix = raw.split('@').first.trim();
      return prefix.isNotEmpty ? prefix : raw;
    }
    if (raw.length >= 20 && !raw.contains(' ')) {
      return 'Sinh viên';
    }
    return raw.isNotEmpty ? raw : 'Sinh viên';
  }

  /// Email hoặc mã định danh phụ ở dòng 2 (chuẩn hoá)
  String get uploaderSubtitle {
    final email = uploaderEmail.trim();
    if (email.isNotEmpty) return email;

    final raw = uploadedBy.trim();
    if (raw.contains('@')) return raw;
    final uid = uploaderUid.trim().isNotEmpty ? uploaderUid.trim() : raw;
    if (uid.length >= 20 && !uid.contains(' ')) {
      return 'UID: ${uid.substring(0, 8)}...';
    }
    return email.isNotEmpty ? email : (uid.isNotEmpty ? uid : 'Chưa có email');
  }

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  SrsReport copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? uploadedBy,
    String? uploaderEmail,
    String? uploaderUid,
    DateTime? uploadDate,
    String? status,
    String? storagePath,
    String? downloadUrl,
  }) {
    return SrsReport(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploaderEmail: uploaderEmail ?? this.uploaderEmail,
      uploaderUid: uploaderUid ?? this.uploaderUid,
      uploadDate: uploadDate ?? this.uploadDate,
      status: status ?? this.status,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}
