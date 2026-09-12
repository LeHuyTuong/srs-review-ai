/// Wraps file_picker 12.x. Verified against file_picker 12.2.0 /
/// file_picker_platform_interface 3.3.0 on 2026-09-09:
///   * `pickFile()` returns `PlatformFile?` (null == user cancelled)
///   * `FilePickerResult` and `withData:` no longer exist
///   * bytes come from `await file.readAsBytes()`, size from `await length()`
///
/// Every tutorial written for v11 or earlier will fail to compile here, which
/// is exactly why this is the only file in the app that touches the picker.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/srs_document.dart';

class PickedDocument {
  const PickedDocument({
    required this.fileName,
    required this.bytes,
    required this.sizeBytes,
    this.path,
  });

  final String fileName;
  final Uint8List bytes;
  final int sizeBytes;

  /// Present on desktop/Android file paths, absent for provider-backed URIs.
  /// Needed later for the PDF viewer's jump-to-page feature.
  final String? path;
}

class FilePickerService {
  const FilePickerService();

  /// Client-side cap, raised to 30 MB by product decision (2026-09-10) so
  /// image-heavy SRS exports still fit; refuse earlier than a failed upload
  /// so the user gets a fast, clear answer.
  static const int maxSizeBytes = 30 * 1024 * 1024;

  /// Returns null when the user cancels. Throws [ParseException] for a file we
  /// can never handle, so the caller has exactly two outcomes to render.
  Future<PickedDocument?> pickSrsFile({
    void Function(String status)? onStatus,
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose an SRS document',
      type: FileType.custom,
      allowedExtensions: kSupportedDocumentExtensions.toList(growable: false),
    );
    if (file == null) return null;

    final extension = (file.extension ?? '').toLowerCase();
    if (!kSupportedDocumentExtensions.contains(extension)) {
      throw ParseException(
        'Only PDF and DOCX files are supported${extension.isEmpty ? '' : ' (got .$extension)'}.',
      );
    }

    final size = file.lengthSync() ?? await file.length();
    if (size > maxSizeBytes) {
      throw ParseException(
        'This file is ${(size / 1024 / 1024).toStringAsFixed(1)} MB. '
        'The limit is ${maxSizeBytes ~/ (1024 * 1024)} MB.',
      );
    }

    // readAsBytes is the long pole for a large file; surface it before the
    // blocking read so the progress card appears immediately.
    onStatus?.call(
      'Reading ${file.name} (${(size / 1024 / 1024).toStringAsFixed(1)} MB)…',
    );
    await Future<void>.delayed(Duration.zero);

    return PickedDocument(
      fileName: file.name,
      bytes: await file.readAsBytes(),
      sizeBytes: size,
      path: file.path,
    );
  }
}
