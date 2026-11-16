import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Uploads through Cloudinary's unsigned preset. No API secret is shipped in app.
///
/// Dùng `package:http` thay `dart:io HttpClient`: HttpClient ném
/// `Unsupported operation: Platform._version` ngay khi khởi tạo trên web,
/// làm provider rơi vào error state và nút "Nộp tài liệu" chết.
class CloudinaryUploadService {
  CloudinaryUploadService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Giá trị lớn nhất an toàn cho nextInt trên cả VM lẫn web.
  static const _boundaryMax = 0x7fffffff;

  Future<Uri> upload({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    void Function(double progress)? onProgress,
  }) async {
    const cloudNameDefine = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
    const uploadPresetDefine = String.fromEnvironment(
      'CLOUDINARY_UPLOAD_PRESET',
    );
    final cloudName = _configuredValue(
      'CLOUDINARY_CLOUD_NAME',
      cloudNameDefine,
    );
    final uploadPreset = _configuredValue(
      'CLOUDINARY_UPLOAD_PRESET',
      uploadPresetDefine,
    );
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw const CloudinaryUploadException(
        'Thiếu cấu hình CLOUDINARY_CLOUD_NAME hoặc CLOUDINARY_UPLOAD_PRESET.',
      );
    }

    // Không dịch bit 1 sang trái 32 lần: trên web phép dịch là 32-bit nên ra 0 và
    // nextInt(0) ném RangeError ngay khi bấm "Nộp tài liệu".
    final random = Random.secure();
    final boundary =
        '----srs${random.nextInt(_boundaryMax)}${random.nextInt(_boundaryMax)}';
    final request = http.StreamedRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/$cloudName/auto/upload'),
    );
    request.headers['content-type'] = 'multipart/form-data; boundary=$boundary';

    final bodyBuilder = BytesBuilder(copy: false);
    void writeAscii(String value) => bodyBuilder.add(utf8.encode(value));
    void field(String name, String value) {
      writeAscii('--$boundary\r\n');
      writeAscii('Content-Disposition: form-data; name="$name"\r\n\r\n');
      writeAscii('$value\r\n');
    }

    field('upload_preset', uploadPreset);
    field('folder', folder);
    writeAscii('--$boundary\r\n');
    writeAscii(
      'Content-Disposition: form-data; name="file"; filename="${_safeName(fileName)}"\r\n',
    );
    writeAscii('Content-Type: ${_contentType(fileName)}\r\n\r\n');
    bodyBuilder.add(bytes);
    writeAscii('\r\n--$boundary--\r\n');

    final payload = bodyBuilder.takeBytes();
    request.contentLength = payload.length;

    onProgress?.call(0.0);
    final pending = _client.send(request);
    // Trên web trình duyệt gom cả body rồi mới gửi, nên tiến độ ở đây là tiến
    // độ đẩy vào request; giữ dưới 95% tới khi server trả lời thật.
    const chunkSize = 16 * 1024;
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = (offset + chunkSize < payload.length)
          ? offset + chunkSize
          : payload.length;
      request.sink.add(Uint8List.sublistView(payload, offset, end));
      onProgress?.call(0.95 * end / payload.length);
      await Future<void>.delayed(Duration.zero);
    }
    await request.sink.close();

    final response = await http.Response.fromStream(await pending);
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudinaryUploadException(errorMessage(response.statusCode, body));
    }
    final decoded = jsonDecode(body);
    final url = decoded is Map<String, dynamic> ? decoded['secure_url'] : null;
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com') {
      throw const CloudinaryUploadException(
        'Cloudinary không trả về URL hợp lệ.',
      );
    }
    onProgress?.call(1.0);
    return uri;
  }

  /// Câu cho sinh viên đọc: không lộ JSON thô của Cloudinary.
  static String errorMessage(int status, String body) {
    String? reason;
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? error['message'] : null;
      if (message is String && message.trim().isNotEmpty) {
        reason = message.trim();
      }
    } on FormatException {
      reason = null;
    }
    if (status >= 500 || reason == null) {
      return 'Máy chủ lưu tệp đang lỗi (mã $status). Vui lòng thử lại sau ít phút.';
    }
    if (status == 400 && reason.toLowerCase().contains('invalid')) {
      return 'Tệp bị hỏng hoặc sai định dạng nên không tải lên được. '
          'Hãy xuất lại tệp rồi nộp lại.';
    }
    return 'Không tải được tệp lên (mã $status): $reason';
  }

  String _configuredValue(String key, String defineValue) {
    final dotenvValue = dotenv.isInitialized ? dotenv.env[key]?.trim() : null;
    return dotenvValue != null && dotenvValue.isNotEmpty
        ? dotenvValue
        : defineValue.trim();
  }

  String _safeName(String name) =>
      name.split(RegExp(r'[/\\]')).last.replaceAll('"', '_');

  String _contentType(String name) => switch (name
      .split('.')
      .last
      .toLowerCase()) {
    'pdf' => 'application/pdf',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'md' => 'text/markdown',
    _ => 'application/octet-stream',
  };
}

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

final cloudinaryUploadServiceProvider = Provider<CloudinaryUploadService>((
  ref,
) {
  return CloudinaryUploadService();
});
