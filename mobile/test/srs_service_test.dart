import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:srs_review_ai_mobile/services/srs_service.dart';

void main() {
  final bytes = Uint8List.fromList(List<int>.filled(1234, 7));

  Map<String, Object?> intentBody() => {
    'asset_id': 'abc123',
    'upload_url': 'https://api.cloudinary.com/v1_1/demo/raw/upload',
    'fields': {
      'public_id': 'srs_reports/abc123/otes.pdf',
      'timestamp': '1',
      'api_key': 'k',
      'signature': 'sig',
    },
    'intent_token': 'tok',
  };

  test(
    'intent -> Cloudinary -> finalize, app token never sent to Cloudinary',
    () async {
      final calls = <http.BaseRequest>[];
      Map<String, dynamic>? intentRequest;
      final client = MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/assets/upload-intents') {
          intentRequest = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(intentBody()), 201);
        }
        if (request.url.host == 'api.cloudinary.com') {
          return http.Response(
            '{"public_id":"srs_reports/abc123/otes.pdf"}',
            200,
          );
        }
        if (request.url.path == '/assets/abc123/finalize') {
          expect(jsonDecode(request.body), {'intent_token': 'tok'});
          return http.Response(
            jsonEncode({
              'id': 'abc123',
              'fileName': 'otes.pdf',
              'fileSize': 1234,
              'storagePath': 'srs_reports/abc123/otes.pdf',
              'downloadUrl': 'https://res.cloudinary.com/x.pdf',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final service = CloudinarySrsService(
        baseUrl: 'http://server.test',
        appToken: 'app-secret',
        client: client,
        currentUid: () => 'uid-1',
      );

      final result = await service.uploadSrs(
        fileName: 'otes.pdf',
        bytes: bytes,
        uploadedByEmail: 'gv@fpt.edu.vn',
      );

      expect(result.id, 'abc123');
      expect(result.downloadUrl, 'https://res.cloudinary.com/x.pdf');
      expect(intentRequest, containsPair('owner_uid', 'uid-1'));
      expect(intentRequest, containsPair('source', 'mobile'));
      expect(intentRequest, containsPair('size_bytes', 1234));
      expect(calls.map((c) => c.url.host), [
        'server.test',
        'api.cloudinary.com',
        'server.test',
      ]);
      expect(calls[0].headers['X-App-Token'], 'app-secret');
      expect(calls[1].headers.containsKey('X-App-Token'), isFalse);
    },
  );

  test('chưa đăng nhập thì không gọi mạng', () async {
    var called = false;
    final service = CloudinarySrsService(
      baseUrl: 'http://server.test',
      client: MockClient((_) async {
        called = true;
        return http.Response('', 500);
      }),
      currentUid: () => null,
    );

    await expectLater(
      service.uploadSrs(fileName: 'a.pdf', bytes: bytes, uploadedByEmail: ''),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test(
    'server detail bubbles up (file over the Cloudinary Free cap)',
    () async {
      final service = CloudinarySrsService(
        baseUrl: 'http://server.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'vượt trần 10 MB'}),
            413,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        currentUid: () => 'uid-1',
      );

      await expectLater(
        service.uploadSrs(fileName: 'a.pdf', bytes: bytes, uploadedByEmail: ''),
        throwsA(
          isA<SrsUploadException>()
              .having((e) => e.statusCode, 'statusCode', 413)
              .having((e) => e.message, 'message', contains('10 MB')),
        ),
      );
    },
  );

  test('finalize failure does not report success', () async {
    final service = CloudinarySrsService(
      baseUrl: 'http://server.test',
      client: MockClient((request) async {
        if (request.url.path == '/assets/upload-intents') {
          return http.Response(jsonEncode(intentBody()), 201);
        }
        if (request.url.host == 'api.cloudinary.com') {
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({'detail': 'Firestore write failed'}),
          502,
        );
      }),
      currentUid: () => 'uid-1',
    );

    await expectLater(
      service.uploadSrs(fileName: 'a.pdf', bytes: bytes, uploadedByEmail: ''),
      throwsA(
        isA<SrsUploadException>().having((e) => e.statusCode, 'code', 502),
      ),
    );
  });
}
