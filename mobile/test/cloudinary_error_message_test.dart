import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/cloudinary_upload_service.dart';

void main() {
  // SV từng thấy nguyên văn `Cloudinary trả lỗi 400: {"error":{...}}` (11/11).
  test('PDF hỏng: câu tiếng Việt, không lộ JSON', () {
    final m = CloudinaryUploadService.errorMessage(
      400,
      '{"error":{"message":"Invalid PDF file"}}',
    );
    expect(m, contains('hỏng'));
    expect(m, isNot(contains('{')));
  });

  test('4xx khác: nêu mã và lời của Cloudinary, không JSON', () {
    final m = CloudinaryUploadService.errorMessage(
      413,
      '{"error":{"message":"File size too large"}}',
    );
    expect(m, contains('413'));
    expect(m, contains('File size too large'));
    expect(m, isNot(contains('{')));
  });

  test('5xx hoặc body không phải JSON: bảo thử lại', () {
    expect(
      CloudinaryUploadService.errorMessage(502, '<html>'),
      contains('thử lại'),
    );
  });
}
