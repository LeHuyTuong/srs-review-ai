import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/cloudinary_upload_service.dart';

// Chạy được trên web: `flutter test --platform chrome test/cloudinary_upload_web_test.dart
//   --dart-define=CLOUDINARY_CLOUD_NAME=demo --dart-define=CLOUDINARY_UPLOAD_PRESET=p`.
// Trên web bản cũ ném RangeError khi tạo boundary multipart.
void main() {
  test(
    'upload dựng multipart hợp lệ và trả secure_url',
    () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'secure_url': 'https://res.cloudinary.com/demo/raw/upload/x.pdf',
          }),
          200,
        );
      });
      final progress = <double>[];
      final uri = await CloudinaryUploadService(client: client).upload(
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
        fileName: 'bai-nop.pdf',
        folder: 'srs',
        onProgress: progress.add,
      );
      expect(uri.host, 'res.cloudinary.com');
      expect(seen.url.path, endsWith('/auto/upload'));
      final type = seen.headers['content-type']!;
      expect(type, startsWith('multipart/form-data; boundary=----srs'));
      final body = utf8.decode(seen.bodyBytes, allowMalformed: true);
      expect(body, contains('name="upload_preset"'));
      expect(body, contains('filename="bai-nop.pdf"'));
      expect(progress.last, 1.0);
    },
    skip: const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').isEmpty
        ? 'cần --dart-define CLOUDINARY_*'
        : false,
  );
}
