/// Model đại diện cho báo cáo SRS đã được upload
class SrsReport {
  const SrsReport({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.uploadedBy,
    required this.uploadDate,
    required this.status,
    required this.storagePath,
    this.downloadUrl = '',
  });

  final String id;
  final String fileName;
  final int fileSize; // bytes
  final String uploadedBy;
  final DateTime uploadDate;
  final String status; // 'pending', 'reviewed', 'approved', 'rejected'
  final String storagePath;
  final String downloadUrl;

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
      uploadDate: uploadDate ?? this.uploadDate,
      status: status ?? this.status,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}
