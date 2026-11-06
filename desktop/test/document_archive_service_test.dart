// The desktop half of server/tests/test_assets.py: what the client SENDS,
// to whom, and that the app token never leaks to Cloudinary.
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/document_import/services/document_archive_service.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._script);

  final Queue<ResponseBody> _script;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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

Map<String, dynamic> _intent() => {
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

void main() {
  final bytes = Uint8List.fromList(List<int>.filled(1234, 7));

  ({DocumentArchiveService service, _ScriptedAdapter api, _ScriptedAdapter up})
  build(List<ResponseBody> apiScript, List<ResponseBody> uploadScript) {
    final api = _ScriptedAdapter(Queue.of(apiScript));
    final up = _ScriptedAdapter(Queue.of(uploadScript));
    final service = DocumentArchiveService(
      api: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'))
        ..httpClientAdapter = api,
      upload: Dio()..httpClientAdapter = up,
      appToken: 'app-secret',
    );
    return (service: service, api: api, up: up);
  }

  test('intent -> Cloudinary -> finalize returns the Firestore row', () async {
    final h = build(
      [
        _json(_intent(), status: 201),
        _json({
          'id': 'abc123',
          'fileName': 'otes.pdf',
          'fileSize': 1234,
          'storagePath': 'srs_reports/abc123/otes.pdf',
          'downloadUrl': 'https://res.cloudinary.com/x.pdf',
        }),
      ],
      [
        _json({'public_id': 'srs_reports/abc123/otes.pdf'}),
      ],
    );

    final archived = await h.service.archive(
      fileName: 'otes.pdf',
      bytes: bytes,
      uploadedBy: 'user-1',
    );

    expect(archived.id, 'abc123');
    expect(archived.downloadUrl, 'https://res.cloudinary.com/x.pdf');
    expect(h.api.requests.map((r) => r.uri.path), [
      '/assets/upload-intents',
      '/assets/abc123/finalize',
    ]);
    expect(h.api.requests.first.data, {
      'file_name': 'otes.pdf',
      'size_bytes': 1234,
      'source': 'desktop',
      'uploaded_by': 'user-1',
    });
    expect(h.api.requests.first.headers['X-App-Token'], 'app-secret');
    expect(h.api.requests.last.data, {'intent_token': 'tok'});

    final upload = h.up.requests.single;
    expect(upload.uri.toString(), _intent()['upload_url']);
    expect(upload.headers.containsKey('X-App-Token'), isFalse);
    final form = upload.data as FormData;
    expect(Map.fromEntries(form.fields), containsPair('signature', 'sig'));
    expect(form.files.single.key, 'file');
  });

  test('a server refusal surfaces its detail and skips Cloudinary', () async {
    final h = build([
      _json({'detail': 'Tệp vượt trần 10 MB'}, status: 413),
    ], []);

    await expectLater(
      h.service.archive(fileName: 'big.pdf', bytes: bytes, uploadedBy: 'u'),
      throwsA(
        isA<DocumentArchiveException>()
            .having((e) => e.statusCode, 'statusCode', 413)
            .having((e) => e.message, 'message', contains('10 MB')),
      ),
    );
    expect(h.up.requests, isEmpty);
  });

  test('finalize failure is an error, never a silent success', () async {
    final h = build(
      [
        _json(_intent(), status: 201),
        _json({'detail': 'Firestore write failed'}, status: 502),
      ],
      [_json({})],
    );

    await expectLater(
      h.service.archive(fileName: 'otes.pdf', bytes: bytes, uploadedBy: 'u'),
      throwsA(
        isA<DocumentArchiveException>().having(
          (e) => e.statusCode,
          'statusCode',
          502,
        ),
      ),
    );
  });
}
