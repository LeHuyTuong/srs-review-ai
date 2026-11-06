import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef StudentFileDialog = Future<PlatformFile?> Function(
  List<String> allowedExtensions,
);

class PickedStudentSrsFile {
  const PickedStudentSrsFile({
    required this.fileName,
    required this.extension,
    required this.bytes,
    required this.sizeBytes,
  });

  final String fileName;
  final String extension;
  final Uint8List bytes;
  final int sizeBytes;
}

/// Native picker boundary. Tests can inject [picker] without a platform channel.
class StudentFilePickerService {
  const StudentFilePickerService({StudentFileDialog? picker})
    : _picker = picker ?? _showPicker;

  final StudentFileDialog _picker;

  static Future<PlatformFile?> _showPicker(List<String> allowedExtensions) =>
      FilePicker.pickFile(
    dialogTitle: 'Chọn tài liệu SRS',
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );

  Future<PickedStudentSrsFile?> pickSrsFile({
    required int maxSizeBytes,
    required List<String> allowedExtensions,
    void Function(String message)? onStatus,
  }) async {
    final allowed = allowedExtensions
        .map((extension) => extension.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .where(const {'pdf', 'docx', 'md'}.contains)
        .toSet();
    if (allowed.isEmpty) {
      throw const StudentFileException('Chưa cấu hình định dạng tệp được phép.');
    }
    final file = await _picker(allowed.toList(growable: false));
    if (file == null) return null;

    final extension = (file.extension ?? '').toLowerCase();
    if (!allowed.contains(extension)) {
      throw StudentFileException(
        'Chỉ hỗ trợ tệp ${allowed.map((type) => type.toUpperCase()).join(', ')}.',
      );
    }

    final size = file.lengthSync() ?? await file.length();
    if (size <= 0) {
      throw const StudentFileException('Tệp rỗng hoặc không thể đọc.');
    }
    if (size > maxSizeBytes) {
      final maxMb = maxSizeBytes ~/ (1024 * 1024);
      final actualMb = (size / (1024 * 1024)).toStringAsFixed(1);
      throw StudentFileException(
        'Tệp có dung lượng $actualMb MB, vượt giới hạn $maxMb MB.',
      );
    }

    onStatus?.call('Đang đọc ${file.name}…');
    await Future<void>.delayed(Duration.zero);
    final bytes = await file.readAsBytes();
    if (bytes.length != size) {
      throw const StudentFileException('Không đọc đủ dữ liệu của tệp.');
    }
    return PickedStudentSrsFile(
      fileName: file.name,
      extension: extension,
      bytes: bytes,
      sizeBytes: size,
    );
  }
}

class StudentFileException implements Exception {
  const StudentFileException(this.message);
  final String message;

  @override
  String toString() => message;
}
