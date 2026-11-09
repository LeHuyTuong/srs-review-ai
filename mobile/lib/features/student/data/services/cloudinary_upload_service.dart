import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uploads through Cloudinary's unsigned preset. No API secret is shipped in app.
class CloudinaryUploadService {
  CloudinaryUploadService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<Uri> upload({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    void Function(double progress)? onProgress,
  }) async {
    const cloudNameDefine = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
    const uploadPresetDefine = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
    final cloudName = _configuredValue('CLOUDINARY_CLOUD_NAME', cloudNameDefine);
    final uploadPreset = _configuredValue(
      'CLOUDINARY_UPLOAD_PRESET',
      uploadPresetDefine,
    );
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw const CloudinaryUploadException(
        'Thiếu cấu hình CLOUDINARY_CLOUD_NAME hoặc CLOUDINARY_UPLOAD_PRESET.',
      );
    }

    final boundary = '----srs${Random.secure().nextInt(1 << 32)}';
    final request = await _client.postUrl(
      Uri.https('api.cloudinary.com', '/v1_1/$cloudName/auto/upload'),
    );
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );

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

    const chunkSize = 16 * 1024;
    var sent = 0;
    onProgress?.call(0.0);
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = (offset + chunkSize < payload.length)
          ? offset + chunkSize
          : payload.length;
      request.add(Uint8List.sublistView(payload, offset, end));
      await request.flush();
      sent = end;
      onProgress?.call(sent / payload.length);
    }

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudinaryUploadException(
        'Cloudinary trả lỗi ${response.statusCode}: $body',
      );
    }
    final decoded = jsonDecode(body);
    final url = decoded is Map<String, dynamic> ? decoded['secure_url'] : null;
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || uri.scheme != 'https' || uri.host != 'res.cloudinary.com') {
      throw const CloudinaryUploadException('Cloudinary không trả về URL hợp lệ.');
    }
    onProgress?.call(1.0);
    return uri;
  }

  String _configuredValue(String key, String defineValue) {
    final dotenvValue = dotenv.isInitialized ? dotenv.env[key]?.trim() : null;
    return dotenvValue != null && dotenvValue.isNotEmpty
        ? dotenvValue
        : defineValue.trim();
  }

  String _safeName(String name) =>
      name.split(RegExp(r'[/\\]')).last.replaceAll('"', '_');

  String _contentType(String name) => switch (name.split('.').last.toLowerCase()) {
    'pdf' => 'application/pdf',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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

final cloudinaryUploadServiceProvider = Provider<CloudinaryUploadService>((ref) {
  return CloudinaryUploadService();
});
