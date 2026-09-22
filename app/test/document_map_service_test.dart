// Tests for the server document-anatomy client (`/documents/analyze` +
// `/documents/render`). Same scripted-adapter pattern as
// upload_service_test.dart: assertions are about what the client SENDS, and
// they mirror server/tests/test_docmap.py, which pins what the server answers.
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/document_map_service.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._script);

  final Queue<ResponseBody> _script;
  final List<({String method, String path, Object? data})> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((
      method: options.method,
      path: options.uri.path,
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

ResponseBody _png(List<int> bytes) => ResponseBody.fromBytes(
  bytes,
  200,
  headers: {
    Headers.contentTypeHeader: ['image/png'],
  },
);

Map<String, dynamic> _analyzeBody() => {
  'version': '1',
  'page_count': 3,
  'toc_source': 'bookmarks',
  'sections': [
    {'title': '4. Design', 'level': 1, 'start_page': 1, 'end_page': 2},
  ],
  'pages': [
    {'index': 0, 'text_length': 900, 'figures': <Map<String, dynamic>>[]},
    {
      'index': 1,
      'text_length': 0,
      'figures': [
        {
          'kind': 'drawing',
          'bbox': [72.0, 120.0, 312.0, 360.0],
          'xref': null,
          'pixel_width': null,
          'pixel_height': null,
          'drawing_items': 42,
          'embedded_xml': null,
          'embedded_xml_truncated': false,
          'readable': 'vision-required',
        },
      ],
    },
    {'index': 2, 'text_length': 40, 'figures': <Map<String, dynamic>>[]},
  ],
};

void main() {
  group('DocumentMapService.analyzeDocument', () {
    test('presigns, PUTs the bytes, then analyzes by upload:// uri', () async {
      final adapter = _ScriptedAdapter(
        Queue.of([
          _json({
            'upload_uri': '/uploads/abc-otes.pdf',
            'put_url': '/uploads/abc-otes.pdf?token=TOK',
            'method': 'PUT',
            'expires_at': '2026-09-16T01:00:00+00:00',
            'upload_token': 'TOK',
          }),
          _json({
            'key': 'abc-otes.pdf',
            'size': 3,
            'sha256': 'deadbeef',
          }, status: 201),
          _json(_analyzeBody()),
        ]),
      );
      final service = DocumentMapService(
        dio: Dio()
          ..httpClientAdapter = adapter
          ..options.headers['X-App-Token'] = 'secret',
        baseUrl: 'http://127.0.0.1:8000',
      );

      final analysis = await service.analyzeDocument(
        fileName: 'otes.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(adapter.requests.map((r) => r.method).toList(), [
        'POST',
        'PUT',
        'POST',
      ]);
      expect(adapter.requests[1].path, '/uploads/abc-otes.pdf');
      expect(adapter.requests[2].path, '/documents/analyze');
      expect(adapter.requests[2].data, {'uri': 'upload://abc-otes.pdf'});
      // The docmap comes back parsed, with the figure bbox intact.
      expect(analysis.uploadUri, 'upload://abc-otes.pdf');
      expect(analysis.map.pageCount, 3);
      expect(analysis.map.figurePages, [1]);
      expect(analysis.map.sectionForPage(2)!.title, '4. Design');
      expect(analysis.map.figuresOn(1).single.bbox, [
        72.0,
        120.0,
        312.0,
        360.0,
      ]);
    });
  });

  group('DocumentMapService.renderFigure', () {
    test('posts the bbox and returns the PNG bytes', () async {
      final adapter = _ScriptedAdapter(
        Queue.of([
          _png([0x89, 0x50, 0x4E, 0x47]),
        ]),
      );
      final service = DocumentMapService(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'http://127.0.0.1:8000',
      );

      final bytes = await service.renderFigure(
        uploadUri: 'upload://abc-otes.pdf',
        pageIndex: 1,
        bbox: const [72.0, 120.0, 312.0, 360.0],
      );

      expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
      expect(adapter.requests.single.path, '/documents/render');
      expect(adapter.requests.single.data, {
        'uri': 'upload://abc-otes.pdf',
        'page_index': 1,
        'bbox': [72.0, 120.0, 312.0, 360.0],
        'scale': 3.0,
      });
    });

    test('accepts a null bbox (whole page) and a custom scale', () async {
      final adapter = _ScriptedAdapter(
        Queue.of([
          _png([1, 2, 3]),
        ]),
      );
      final service = DocumentMapService(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'http://127.0.0.1:8000',
      );

      await service.renderFigure(
        uploadUri: 'upload://k',
        pageIndex: 0,
        scale: 4.0,
      );

      expect(adapter.requests.single.data, {
        'uri': 'upload://k',
        'page_index': 0,
        'bbox': null,
        'scale': 4.0,
      });
    });
  });
}
