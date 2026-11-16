/// Contract additions WP5 leans on: `ApiException.detail`, the PATCH verb,
/// and the class write key header.
///
/// The point of each test is the DECISION, not the HTTP mechanics:
/// * two 409 bodies must produce two DIFFERENT mapped reasons — the two
///   decision failures lead to two different teacher actions;
/// * `class_missing` must stay ONE ambiguous reason — splitting it would make
///   the app an existence oracle through the write path (ADR-0017);
/// * `X-Class-Key` must ride exactly on the class-scoped writes that ADR-0017
///   assigns it to, and never on ordinary POST/PUT/DELETE writes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/features/teacher/data/teacher_repository.dart';
import 'package:srs_review_ai/features/teacher/view_model/teacher_reasons.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._script);

  final List<Object> _script;

  int calls = 0;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    requests.add(options);
    final next = _script.removeAt(0);
    if (next is ResponseBody) return next;
    throw StateError('unsupported scripted action: $next');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    'content-type': const <String>['application/json'],
  },
);

ApiService _service(_ScriptedAdapter adapter) => ApiService(
  dio: Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = adapter,
  baseUrl: 'http://localhost:8000',
);

void main() {
  group('ApiException carries the proxy detail', () {
    test('a 409 not_in_class response lands in exception.detail', () async {
      final adapter = _ScriptedAdapter([
        _json({'detail': 'not_in_class'}, status: 409),
      ]);
      final service = _service(adapter);

      await expectLater(
        service.write(
          '/submissions/s1/decision',
          body: {'decision': 'approved'},
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.detail, 'detail', 'not_in_class'),
        ),
      );
      expect(adapter.requests.single.method, 'POST');
    });

    test(
      'a 409 class_missing response keeps its ONE ambiguous reason',
      () async {
        final adapter = _ScriptedAdapter([
          _json({'detail': 'class_missing'}, status: 409),
        ]);
        final service = _service(adapter);

        await expectLater(
          service.write(
            '/submissions/s1/decision',
            body: {'decision': 'approved'},
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having((e) => e.detail, 'detail', 'class_missing'),
          ),
        );
      },
    );

    test(
      'the two 409 reasons map to two different one-line messages',
      () async {
        Future<String> reasonOf(String detail) async {
          final adapter = _ScriptedAdapter([
            _json({'detail': detail}, status: 409),
          ]);
          final service = _service(adapter);
          try {
            await service.write(
              '/submissions/s1/decision',
              body: {'decision': 'approved'},
            );
          } on ApiException catch (error) {
            return error.detail ?? '';
          }
          return '';
        }

        final reasons = <String>[
          await reasonOf('not_in_class'),
          await reasonOf('class_missing'),
        ];
        expect(reasons, ['not_in_class', 'class_missing']);
        final notInClassMessage = teacherDecisionFailureMessage(
          ApiException('x', detail: 'not_in_class'),
        );
        final classMissingMessage = teacherDecisionFailureMessage(
          ApiException('x', detail: 'class_missing'),
        );
        expect(notInClassMessage, isNot(classMissingMessage));
        expect(
          classMissingMessage,
          contains('hoặc'),
          reason:
              'the class_missing message must keep ADR-0017\'s deliberate '
              '"missing class OR wrong key" ambiguity on screen',
        );
      },
    );

    test(
      'a body without detail yields a null detail, not a guessed one',
      () async {
        final adapter = _ScriptedAdapter([
          _json({'msg': 'no reason here'}, status: 400),
        ]);
        final service = _service(adapter);

        await expectLater(
          service.write('/whatever'),
          throwsA(
            isA<ApiException>().having((e) => e.detail, 'detail', isNull),
          ),
        );
      },
    );
  });

  group('PATCH verb and X-Class-Key', () {
    test('PATCH sends the write key header when one is given', () async {
      final adapter = _ScriptedAdapter([
        _json({'id': 'c1', 'name': 'Lớp 01', 'createdAt': '', 'updatedAt': ''}),
      ]);
      final service = _service(adapter);

      await service.write(
        '/classes/c1',
        method: 'PATCH',
        body: {'name': 'Lớp 01'},
        writeKey: ' key-123 ',
      );
      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(request.headers['X-Class-Key'], 'key-123');
    });

    test('an ordinary POST carries no X-Class-Key', () async {
      final adapter = _ScriptedAdapter([
        _json({'id': 'c1', 'write_key': 'k'}),
      ]);
      final service = _service(adapter);

      await service.write('/classes', body: {'name': 'Lớp 01'});
      expect(
        adapter.requests.single.headers.containsKey('X-Class-Key'),
        isFalse,
      );
    });

    test(
      'DELETE carries the key and PATCH sends no key when none is given',
      () async {
        final adapter = _ScriptedAdapter(<ResponseBody>[
          _json({'deleted': 'c1', 'unfiled': 0, 'dangling': <String>[]}),
          _json({'id': 'c1'}),
        ]);
        final service = _service(adapter);

        await service.write('/classes/c1', method: 'DELETE', writeKey: 'k');
        await service.write(
          '/classes/c1',
          method: 'PATCH',
          body: {'name': 'x'},
        );
        expect(adapter.requests[0].method, 'DELETE');
        expect(adapter.requests[0].headers['X-Class-Key'], 'k');
        expect(adapter.requests[1].headers.containsKey('X-Class-Key'), isFalse);
      },
    );

    test(
      'an unsupported write verb is an ArgumentError, not a silent GET',
      () async {
        final adapter = _ScriptedAdapter([]);
        final service = _service(adapter);

        await expectLater(
          service.write('/x', method: 'GET'),
          throwsArgumentError,
        );
        expect(adapter.calls, 0);
      },
    );
  });

  group('TeacherRepository write-then-read contract', () {
    test(
      'decide sends the class key and ignores the thin answered row',
      () async {
        final adapter = _ScriptedAdapter([
          // The THIN row the decision route answers: no group, no project, no
          // history. The repository returns void, so nothing can parse it.
          _json({
            'id': 's1',
            'status': 'approved',
            'decidedAt': '2026-09-27T10:00:00Z',
            'updatedAt': '2026-09-27T10:00:00Z',
            'class_id': 'c1',
          }),
        ]);
        final repository = TeacherRepository(_service(adapter));

        await repository.decide(
          submissionId: 's1',
          writeKey: 'key-c1',
          decision: TeacherDecision.approved,
        );
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.headers['X-Class-Key'], 'key-c1');
        expect(jsonEncode(request.data), contains('approved'));
      },
    );

    test(
      'deleteClass parses unfiled/dangling so the UI can warn honestly',
      () async {
        final adapter = _ScriptedAdapter([
          _json({
            'deleted': 'c1',
            'unfiled': 2,
            'dangling': <String>['s9'],
          }),
        ]);
        final repository = TeacherRepository(_service(adapter));

        final outcome = await repository.deleteClass('c1', 'key-c1');
        expect(outcome.deletedId, 'c1');
        expect(outcome.unfiled, 2);
        expect(outcome.dangling, ['s9']);
        expect(outcome.needsWarning, isTrue);
      },
    );

    test('renameClass rides PATCH with the class key', () async {
      final adapter = _ScriptedAdapter([
        _json({
          'id': 'c1',
          'name': 'Tên mới',
          'createdAt': '2026-09-27T09:00:00Z',
          'updatedAt': '2026-09-27T09:30:00Z',
        }),
      ]);
      final repository = TeacherRepository(_service(adapter));

      final record = await repository.renameClass(
        'c1',
        'key-c1',
        name: 'Tên mới',
      );
      expect(adapter.requests.single.method, 'PATCH');
      expect(adapter.requests.single.headers['X-Class-Key'], 'key-c1');
      expect(record.name, 'Tên mới');
      expect(record.writeKey, 'key-c1');
    });
  });
}
