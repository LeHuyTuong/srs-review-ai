// Ba lỗi nhỏ của form nộp bài sinh viên (test thật 11/11/2026):
// 600 byte hiện "0.00 MB"; dropdown lớp liệt kê mọi lớp; form giữ tệp sau khi nộp.
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

import 'dart:typed_data';

import 'package:srs_review_ai_mobile/features/student/data/services/student_file_picker_service.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/viewmodels/student_upload_view_model.dart';

AcademicSnapshot _snap() => AcademicSnapshot({
  'classes': [
    {'id': 'a', 'code': 'A', 'state': 'active'},
    {'id': 'b', 'code': 'B', 'state': 'active'},
    {'id': 'old', 'code': 'OLD', 'state': 'archived'},
  ],
  'students': [
    {'id': 's1', 'email': 'An@Uni.edu', 'classId': 'b'},
  ],
});

void main() {
  test('kích thước tệp đọc được ở mọi cỡ', () {
    expect(fileSizeLabel(600), '600 B');
    expect(fileSizeLabel(1536), '1.5 KB');
    expect(fileSizeLabel(3 * 1024 * 1024), '3.0 MB');
  });

  test('sinh viên có trong danh sách chỉ thấy lớp của mình', () {
    expect(submittableClasses(_snap(), 'an@uni.edu').map((c) => c.id), ['b']);
  });

  test('chưa có trong danh sách thì thấy mọi lớp chưa lưu trữ', () {
    expect(submittableClasses(_snap(), 'la@gmail.com').map((c) => c.id), [
      'a',
      'b',
    ]);
  });

  test(
    'nộp xong thì form bỏ tệp, giữ lớp/dự án và tên tệp cho thẻ thành công',
    () {
      final picked = StudentUploadState(
        file: PickedStudentSrsFile(
          fileName: 'srs.pdf',
          extension: 'pdf',
          bytes: Uint8List(3),
          sizeBytes: 3,
        ),
        classId: 'a',
        projectId: 'p',
        uploading: true,
      );
      final done = picked.succeeded(Uri.parse('https://x/srs.pdf'));
      expect(done.file, isNull);
      expect(done.uploading, isFalse);
      expect(done.classId, 'a');
      expect(done.projectId, 'p');
      expect(done.submittedFileName, 'srs.pdf');
      expect(done.uploadedUrl.toString(), 'https://x/srs.pdf');
    },
  );
}
