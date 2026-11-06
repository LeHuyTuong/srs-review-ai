import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Uploads through Cloudinary's unsigned preset. No API secret is shipped in app.
class CloudinaryUploadService {
  CloudinaryUploadService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<Uri> upload({
    required Uint8List bytes,
    required String fileName,
    required String folder,
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
    request.headers.contentType = ContentType('multipart', 'form-data',
        parameters: {'boundary': boundary});

    void field(String name, String value) {
      request.write('--$boundary\r\n');
      request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      request.write('$value\r\n');
    }

    field('upload_preset', uploadPreset);
    field('folder', folder);
    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="file"; filename="${_safeName(fileName)}"\r\n',
    );
    request.write('Content-Type: ${_contentType(fileName)}\r\n\r\n');
    request.add(bytes);
    request.write('\r\n--$boundary--\r\n');

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
