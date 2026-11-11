import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart'
    show AiReviewException;
import 'package:srs_review_ai_mobile/core/services/drawio_review_service.dart';

class _FakeUser implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'tok-123';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  _FakeAuth(this.currentUser);
  @override
  final User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ok = {
  'engine': 'uc-review',
  'deterministic': true,
  'title': 'Admin',
  'error_count': 1,
  'review_count': 2,
  'actors': 1,
  'use_cases': 9,
  'findings': [
    {'num': 1, 'severity': 'error', 'what': 'Thiếu actor', 'fix': 'Thêm actor'},
    {'num': 2, 'severity': 'review', 'what': 'Tên dài', 'fix': 'Rút gọn'},
  ],
  'read_note': null,
  'reviewed_xml': '<mxfile/>',
};

DrawioReviewService _service(
  http.Client client, {
  String baseUrl = 'http://example.test:8000',
  User? user,
}) => DrawioReviewService(
  baseUrl: baseUrl,
  auth: _FakeAuth(user ?? _FakeUser()),
  client: client,
);

void main() {
  test('gửi xml + Bearer tới /diagram/drawio và đọc findings', () async {
    late http.Request seen;
    final service = _service(
      MockClient((request) async {
        seen = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode(_ok)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await service.review(
      xml: '<mxfile/>',
      fileName: 'uc.drawio',
    );

    expect(seen.url.toString(), 'http://example.test:8000/diagram/drawio');
    expect(seen.headers['authorization'], 'Bearer tok-123');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body, {'xml': '<mxfile/>', 'file_name': 'uc.drawio', 'lang': 'vi'});
    expect(result.errorCount, 1);
    expect(result.reviewCount, 2);
    expect(result.findings.map((f) => f.number), [1, 2]);
    expect(result.findings.first.isError, isTrue);
    expect(result.findings.last.isError, isFalse);
    expect(result.findings.first.what, 'Thiếu actor');
    expect(result.reviewedXml, '<mxfile/>');
  });

  test('chưa cấu hình server → lỗi dễ hiểu, không gọi mạng', () async {
    var called = false;
    final service = _service(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
      baseUrl: '',
    );
    await expectLater(
      service.review(xml: '<mxfile/>'),
      throwsA(
        isA<AiReviewException>().having(
          (e) => e.message,
          'message',
          contains('SRS_API_BASE_URL'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('chưa đăng nhập → báo đăng nhập, không gọi mạng', () async {
    var called = false;
    final service = DrawioReviewService(
      baseUrl: 'http://example.test:8000',
      auth: _FakeAuth(null),
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.review(xml: '<mxfile/>'),
      throwsA(isA<AiReviewException>()),
    );
    expect(called, isFalse);
  });

  for (final status in [400, 413, 422]) {
    test('$status mang lý do của server (không phải "0 lỗi")', () async {
      final service = _service(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'detail': 'Chỉ là ảnh nhúng'})),
            status,
          ),
        ),
      );
      await expectLater(
        service.review(xml: '<mxfile/>'),
        throwsA(
          isA<AiReviewException>().having(
            (e) => e.message,
            'message',
            'Chỉ là ảnh nhúng',
          ),
        ),
      );
    });
  }

  test('401 → yêu cầu đăng nhập lại', () async {
    final service = _service(
      MockClient((_) async => http.Response('{"detail":"x"}', 401)),
    );
    await expectLater(
      service.review(xml: '<mxfile/>'),
      throwsA(
        isA<AiReviewException>().having(
          (e) => e.message,
          'message',
          contains('Đăng nhập lại'),
        ),
      ),
    );
  });

  test('lỗi socket → thông điệp mạng, không lộ stack', () async {
    final service = _service(
      MockClient((_) async => throw http.ClientException('socket')),
    );
    await expectLater(
      service.review(xml: '<mxfile/>'),
      throwsA(
        isA<AiReviewException>().having(
          (e) => e.message,
          'message',
          contains('Không kết nối'),
        ),
      ),
    );
  });
}
