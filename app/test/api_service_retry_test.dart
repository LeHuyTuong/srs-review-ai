/// Retry decisions in [ApiService].
///
/// The point of these tests is the DECISION, not the HTTP mechanics: a dropped
/// connection is worth another attempt, while a quota rejection and a
/// cancellation are not. Retrying those only delays the message the user needs
/// to read, or spends quota they just asked us to stop spending.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/api_service.dart';

/// What the fake transport should do on a given attempt.
enum _Action { ok, dropped }

/// Serves a scripted sequence of outcomes instead of a socket: each entry is
/// either a raw [ResponseBody] (for a chosen status code) or an [_Action].
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._script, {this.cancelAfterFirstCall});

  final Queue<Object> _script;
  final CancelToken? cancelAfterFirstCall;

  /// How many times the transport was actually hit — the whole point of these
  /// tests: retried work shows up here as more than one call.
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final next = _script.removeFirst();
    if (next is ResponseBody) return next;
    return switch (next as _Action) {
      _Action.ok => _json(_okResult),
      _Action.dropped => _dropConnection(options),
    };
  }

  /// Always throws; declared as returning [ResponseBody] so it can sit in a
  /// switch expression arm.
  ResponseBody _dropConnection(RequestOptions options) {
    cancelAfterFirstCall?.cancel('stopped');
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'the wifi gave up',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A minimal, contract-valid review payload.
const Map<String, Object?> _okResult = {
  'contract_version': '1.0.0',
  'requirement_id': 'FR-01',
  'score': 7,
  'issues': <Object>[],
  'model': 'test-model',
};

ResponseBody _json(
  Object body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    'content-type': const <String>['application/json'],
    ...headers,
  },
);

ApiService _service(_FakeAdapter adapter) => ApiService(
  dio: Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = adapter,
  baseUrl: 'http://localhost:8000',
);

void main() {
  group('ApiService retry', () {
    test('a dropped connection is retried and can still succeed', () async {
      final adapter = _FakeAdapter(
        Queue<Object>.of(<Object>[_Action.dropped, _Action.ok]),
      );

      final result = await _service(
        adapter,
      ).review(requirementId: 'FR-01', text: 'The system shall store reports.');

      expect(result.score, 7);
      expect(adapter.calls, 2, reason: 'one failure then one retry');
    });

    test('a quota rejection is final — never retried', () async {
      final adapter = _FakeAdapter(
        Queue<Object>.of(<Object>[_json(const <String, Object?>{}, status: 429)]),
      );

      await expectLater(
        _service(adapter).review(requirementId: 'FR-01', text: 'x'),
        throwsA(
          isA<ApiException>()
            .having(
              (error) => error.statusCode,
              'statusCode',
              429,
            )
            .having(
              // No Retry-After header on the fake response => day-scale
              // fallback must survive so the sentence never comes up blank.
              (error) => error.message,
              'message',
              contains('try again tomorrow'),
            ),
        ),
      );
      expect(
        adapter.calls,
        1,
        reason: '429 will fail identically next time; retrying only delays it',
      );
    });

    test('a quota rejection reports the Retry-After window', () async {
      final adapter = _FakeAdapter(
        Queue<Object>.of(<Object>[
          _json(
            const <String, Object?>{},
            status: 429,
            headers: {
              'retry-after': ['240'],
            },
          ),
        ]),
      );

      await expectLater(
        _service(adapter).review(requirementId: 'FR-01', text: 'x'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Retry in about 4 min'),
          ),
        ),
      );
    });

    test('quotaMessage renders hours, minutes, and the fallback', () {
      expect(
        ApiService.quotaMessage(retryAfterSeconds: 86_400),
        contains('Retry in about 24 h'),
      );
      expect(
        ApiService.quotaMessage(retryAfterSeconds: 90),
        contains('Retry in about 2 min'),
      );
      expect(ApiService.quotaMessage(), contains('try again tomorrow'));
      expect(ApiService.quotaMessage(retryAfterSeconds: 0), contains('tomorrow'));
    });

    test('a run the user cancelled is not retried', () async {
      final token = CancelToken();
      final adapter = _FakeAdapter(
        Queue<Object>.of(<Object>[_Action.dropped, _Action.ok]),
        cancelAfterFirstCall: token,
      );

      await expectLater(
        _service(adapter).review(
          requirementId: 'FR-01',
          text: 'x',
          cancelToken: token,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        adapter.calls,
        1,
        reason: 'cancelling must stop the work, not quietly restart it',
      );
    });
  });
}
