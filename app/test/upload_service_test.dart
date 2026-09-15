// Tests for the presigned-upload client. Pattern copied from
// api_service_retry_test.dart: a scripted HttpClientAdapter instead of a
// socket, so the assertions are about what the client SENDS — the exact
// contract its server-side twin in server/tests/test_uploads.py checks back.
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/upload_service.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._script);

  final Queue<ResponseBody> _script;
  final List<({String method, Uri uri, Object? data})> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((
      method: options.method,
      uri: options.uri,
      data: options.data,
    ));
    return _script.removeFirst();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  final base = Uri.parse('http://127.0.0.1:8000');

  group('UploadService.uploadDocument', () {
    test(
      'presign then PUT the exact bytes to the resolved token URL',
      () async {
        final adapter = _ScriptedAdapter(
          Queue.of([
            _json({
              'upload_uri': '/uploads/abc123-otes.pdf',
              'put_url': '/uploads/abc123-otes.pdf?token=TOK.ENCRYPTED',
              'method': 'PUT',
              'expires_at': '2026-09-14T01:00:00+00:00',
              'upload_token': 'TOK.ENCRYPTED',
            }),
            _json({
              'key': 'abc123-otes.pdf',
              'size': 3,
              'sha256': 'deadbeef',
            }, status: 201),
          ]),
        );
        final service = UploadService(Dio()..httpClientAdapter = adapter);

        final outcome = await service.uploadDocument(
          base: base,
          fileName: 'otes.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        );

        // Presign carries the declaration the server enforces against the
        // actual stream later.
        expect(adapter.requests, hasLength(2));
        final presign = adapter.requests[0];
        expect(presign.method, 'POST');
        expect(presign.uri.path, '/uploads/presign');
        expect(presign.data, {'file_name': 'otes.pdf', 'size_bytes': 3});

        // The PUT goes to the server-assembled URL — token included, base
        // resolved — with the raw bytes and nothing re-minted client-side.
        final put = adapter.requests[1];
        expect(put.method, 'PUT');
        expect(
          put.uri,
          Uri.parse(
            'http://127.0.0.1:8000/uploads/abc123-otes.pdf?token=TOK.ENCRYPTED',
          ),
        );
        expect(put.data, Uint8List.fromList([1, 2, 3]));

        // The reference form the server's resolve() accepts.
        expect(outcome.reference, 'upload://abc123-otes.pdf');
        expect(outcome.key, 'abc123-otes.pdf');
        expect(outcome.sizeBytes, 3);
        expect(outcome.sha256, 'deadbeef');
      },
    );

    test('a 413 at presign propagates as DioException', () async {
      final adapter = _ScriptedAdapter(
        Queue.of([
          ResponseBody.fromString(
            jsonEncode({'detail': 'file exceeds the 41943040-byte ceiling'}),
            413,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        ]),
      );
      final service = UploadService(Dio()..httpClientAdapter = adapter);
      await expectLater(
        service.uploadDocument(
          base: base,
          fileName: 'huge.pdf',
          bytes: Uint8List(10),
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            413,
          ),
        ),
      );
      // Failed before the PUT — no second request was ever attempted.
      expect(adapter.requests, hasLength(1));
    });

    test(
      'base path with trailing slash does not double the separator',
      () async {
        final adapter = _ScriptedAdapter(
          Queue.of([
            _json({
              'upload_uri': '/uploads/k',
              'put_url': '/uploads/k?token=t',
              'method': 'PUT',
              'expires_at': '2026-09-14T01:00:00+00:00',
              'upload_token': 't',
            }),
            _json({'key': 'k', 'size': 0, 'sha256': 'e3b0'}, status: 201),
          ]),
        );
        final service = UploadService(Dio()..httpClientAdapter = adapter);
        await service.uploadDocument(
          base: Uri.parse('http://127.0.0.1:8000/'),
          fileName: 'a.pdf',
          bytes: Uint8List(0),
        );
        expect(adapter.requests[0].uri.path, '/uploads/presign');
      },
    );
  });
}
