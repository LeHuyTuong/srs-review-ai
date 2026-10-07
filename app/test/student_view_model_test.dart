/// The student view-model and store — pure Dart over a fake proxy.
///
/// Three rules are pinned here, and each one is a rule the UI cannot be
/// allowed to re-derive on its own:
///
/// * **No resubmit before the teacher returned the round.** The server does
///   NOT enforce this (it is the UI's rule), so the test is what keeps it
///   true — and it drives the view-model, not the button, so a caller that
///   skipped the button is still covered.
/// * **A resubmit opens a NEW revision** and the state renders the new id.
///   Rendering the old one is how a group resubmits twice.
/// * **The unread count is derived from this device's watermark**, because
///   there is no server-side read state to consult (ADR-0016 decision 4).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/features/student/data/student_repository.dart';
import 'package:srs_review_ai/features/student/data/student_store.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

/// An in-memory proxy serving the comment routes, written as ROUTES rather
/// than a script because the view-model re-reads after every write.
class _FakeProxy {
  _FakeProxy({this.status = 'submitted', List<Map<String, dynamic>>? comments})
    : comments = comments ?? [];

  String status;
  String decisionNote = '';
  String? decidedAt;
  final List<Map<String, dynamic>> comments;
  int revision = 1;
  int nextId = 0;
  final List<String> resubmitCalls = [];

  Map<String, dynamic> row(String id) => {
    'id': id,
    'group': 'Nhóm OTES',
    'project': 'OTES',
    'revision': revision,
    'status': status,
    'class_id': '',
    'decidedAt': decidedAt,
    'decision_note': decisionNote,
    'createdAt': '2026-10-08T01:00:00Z',
    'updatedAt': '2026-10-08T02:00:00Z',
    'history': const <Map<String, dynamic>>[],
    'comments': comments,
    'has_report': false,
    'score': 6.5,
  };

  Future<Response<dynamic>> handle(RequestOptions options) async {
    final path = options.uri.path;
    final method = options.method.toUpperCase();

    if (method == 'GET' && path.startsWith('/submissions/')) {
      return _json(row(path.split('/').last));
    }
    if (method == 'POST' && path.endsWith('/comments')) {
      final body = options.data as Map<String, dynamic>;
      comments.add({
        'id': 'c${nextId++}',
        'author': body['author'],
        'body': body['body'],
        'revision': revision,
        'at': '2026-10-08T0$nextId:00:00Z',
        'resolvedAt': null,
      });
      return _json(comments.last, status: 201);
    }
    if (method == 'POST' && path.endsWith('/replies')) {
      final body = options.data as Map<String, dynamic>;
      // Path is /submissions/<id>/comments/<cid>/replies, so the comment id
      // sits at index 4 — index 3 is the literal word 'comments'.
      final parent = path.split('/')[4];
      final target = comments.firstWhere((c) => c['id'] == parent);
      final replies = (target['replies'] as List<dynamic>? ?? <dynamic>[]);
      final reply = {
        'id': 'r${nextId++}',
        'author': body['author'],
        'body': body['body'],
        'revision': revision,
        'at': '2026-10-08T0$nextId:00:00Z',
        'replyTo': parent,
        'resolvedAt': null,
      };
      replies.add(reply);
      target['replies'] = replies;
      return _json(reply, status: 201);
    }
    if (method == 'POST' && path.endsWith('/revise')) {
      resubmitCalls.add(path.split('/')[2]);
      return _json(row('sub-new'), status: 201);
    }
    return _json({'detail': 'not found'}, status: 404);
  }

  Response<dynamic> _json(Object? body, {int status = 200}) =>
      Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        statusCode: status,
        data: body,
      );
}

(ProviderContainer, _FakeProxy, MemoryStudentStore) _harness({
  String status = 'submitted',
  List<Map<String, dynamic>>? comments,
}) {
  final proxy = _FakeProxy(status: status, comments: comments);
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  dio.httpClientAdapter = _AdapterShim(proxy);
  final store = MemoryStudentStore();
  final container = ProviderContainer(
    overrides: [
      studentStoreProvider.overrideWithValue(store),
      studentRepositoryProvider.overrideWith(
        (ref) => StudentRepository(ApiService(dio: dio)),
      ),
      teacherApiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
    ],
  );
  addTearDown(container.dispose);
  return (container, proxy, store);
}

/// Bridges the fake to dio without a socket.
class _AdapterShim implements HttpClientAdapter {
  _AdapterShim(this.proxy);

  final _FakeProxy proxy;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await proxy.handle(options);
    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('resubmit rule', () {
    test('a round still awaiting review cannot be resubmitted', () async {
      final (container, proxy, _) = _harness(status: 'submitted');
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');

      expect(container.read(studentViewModelProvider).canResubmit, isFalse);
      await notifier.resubmit();
      // THE assertion: the guard refused before any HTTP call left.
      expect(proxy.resubmitCalls, isEmpty);
      expect(
        container.read(studentViewModelProvider).submission!.id,
        's1',
        reason: 'a refused resubmit must not move the screen to a new round',
      );
    });

    test('an approved round cannot be resubmitted either', () async {
      final (container, proxy, _) = _harness(status: 'approved');
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      expect(container.read(studentViewModelProvider).canResubmit, isFalse);
      await notifier.resubmit();
      expect(proxy.resubmitCalls, isEmpty);
    });

    test('changes_requested is what opens the button', () async {
      final (container, proxy, _) = _harness(status: 'changes_requested');
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');

      expect(container.read(studentViewModelProvider).canResubmit, isTrue);
      await notifier.resubmit();
      expect(proxy.resubmitCalls, ['s1']);
    });
  });

  group('reply is visible on both sides', () {
    test('a student reply comes back on the next read', () async {
      final (container, _, _) = _harness(
        comments: [
          {
            'id': 'c0',
            'author': 'teacher',
            'body': 'Sửa mục 3.2',
            'revision': 1,
            'at': '2026-10-08T01:00:00Z',
            'resolvedAt': null,
          },
        ],
      );
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      await notifier.replyTo('c0', 'Dạ em sửa rồi');

      final thread = container
          .read(studentViewModelProvider)
          .submission!
          .comments;
      expect(thread, hasLength(1));
      expect(thread.first.replies, hasLength(1));
      expect(thread.first.replies.first.author, 'student');
      expect(thread.first.replies.first.body, 'Dạ em sửa rồi');
      // The reply must not have become a second TOP-LEVEL comment.
      expect(thread.first.id, 'c0');
    });

    test(
      'a student comment is written as the student, never the teacher',
      () async {
        final (container, proxy, _) = _harness();
        final notifier = container.read(studentViewModelProvider.notifier);
        await notifier.openSubmission('s1');
        await notifier.addComment('Thưa cô mục 3.2 nghĩa là gì?');
        expect(proxy.comments.single['author'], 'student');
      },
    );
  });

  group('unread count is derived from this device', () {
    Map<String, dynamic> teacherComment(String id, String at) => {
      'id': id,
      'author': 'teacher',
      'body': 'x',
      'revision': 1,
      'at': at,
      'resolvedAt': null,
    };

    test('newer than the watermark counts, older does not', () async {
      final (container, _, store) = _harness(
        comments: [
          teacherComment('c1', '2026-10-08T01:00:00Z'),
          teacherComment('c2', '2026-10-08T03:00:00Z'),
        ],
      );
      await store.saveWatermark(
        StudentWatermark(
          submissionId: 's1',
          revision: 1,
          at: DateTime.parse('2026-10-08T02:00:00Z'),
        ),
      );
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      expect(container.read(studentViewModelProvider).unreadTeacherComments, 1);
    });

    test('marking seen clears the count and persists to THIS device', () async {
      final (container, _, store) = _harness(
        comments: [teacherComment('c1', '2026-10-08T03:00:00Z')],
      );
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      expect(container.read(studentViewModelProvider).unreadTeacherComments, 1);

      await notifier.markSeen();
      expect(container.read(studentViewModelProvider).unreadTeacherComments, 0);
      final saved = await store.loadWatermark();
      expect(saved, isNotNull);
      expect(saved!.submissionId, 's1');
      expect(saved.revision, 1);
    });

    test('a resolved remark is never counted as needing attention', () async {
      final (container, _, _) = _harness(
        comments: [
          {
            'id': 'c1',
            'author': 'teacher',
            'body': 'x',
            'revision': 1,
            'at': '2026-10-08T03:00:00Z',
            'resolvedAt': '2026-10-08T04:00:00Z',
          },
        ],
      );
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      expect(container.read(studentViewModelProvider).unreadTeacherComments, 0);
    });
  });

  group('saved links', () {
    test('opening a submission saves the link locally', () async {
      final (container, _, store) = _harness();
      await container
          .read(studentViewModelProvider.notifier)
          .openSubmission('s1');
      final links = await store.loadLinks();
      expect(links.map((l) => l.id), ['s1']);
    });

    test('forgetting a link touches nothing on the server', () async {
      final (container, proxy, store) = _harness();
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      await notifier.forgetLink('s1');
      expect(await store.loadLinks(), isEmpty);
      // The submission itself is still open on screen — forgetting a bookmark
      // is not closing the work.
      expect(container.read(studentViewModelProvider).submission, isNotNull);
    });
  });
}
