import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';

MySubmission _m(String id, String project, String hash, String name) =>
    MySubmission.fromJson(id, {
      'file_name': name,
      'project_id': project,
      'content_hash': hash,
      'uploaded_at': DateTime(2026, 11, 10, 22, 46),
    });

void main() {
  test('sha256 của nội dung tệp, không phụ thuộc tên', () {
    final bytes = Uint8List.fromList(utf8.encode('abc'));
    expect(
      contentHashOf(bytes),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('cùng dự án, cùng hash thì báo trùng kèm tên và giờ nộp', () {
    final mine = [_m('a', 'p1', 'h1', 'srs-v1.pdf')];
    final msg = duplicateUploadMessage(mine, projectId: 'p1', hash: 'h1');
    expect(msg, contains('File giống hệt'));
    expect(msg, contains('srs-v1.pdf'));
    expect(msg, contains('22:46 10/11/2026'));
  });

  test('khác dự án, khác hash hoặc bài cũ không có hash thì không chặn', () {
    final mine = [_m('a', 'p1', 'h1', 'x.pdf'), _m('b', 'p1', '', 'y.pdf')];
    expect(duplicateUploadMessage(mine, projectId: 'p2', hash: 'h1'), isNull);
    expect(duplicateUploadMessage(mine, projectId: 'p1', hash: 'h2'), isNull);
    expect(duplicateUploadMessage(mine, projectId: 'p1', hash: ''), isNull);
  });
}
