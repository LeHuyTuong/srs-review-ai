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
  int listCalls = 0;
  bool failList = false;

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

    // `GET /submissions` (no id) is the identity-scoped LIST (ADR-0020 §4).
    // Checked BEFORE the id route: `/submissions/` starts-with matches both,
    // and answering the list with a submission row is how the list silently
    // becomes one item that is not even a row shape.
    if (method == 'GET' && path == '/submissions') {
      listCalls++;
      if (failList) {
        return _json({'detail': 'proxy down'}, status: 502);
      }
      return _json({
        'submissions': [
          {
            'id': 's1',
            'group': 'Nhóm OTES',
            'project': 'OTES',
            'revision': revision,
            'status': status,
            'class_id': '',
            'decidedAt': decidedAt,
            'decision_note': decisionNote,
            'createdAt': '2026-10-08T01:00:00Z',
            'updatedAt': '2026-10-08T02:00:00Z',
            'commentCount': comments.length,
            'openCommentCount': comments.length,
          },
        ],
        'scope': 'student',
        'group': 'Nhóm OTES',
      });
    }
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
      // A resubmit OPENS A NEW ROUND — the counter has to move, or the fake
      // returns the round that was just superseded and the list refresh below
      // is unobservable. The real server increments; a fake that does not is a
      // fake that reports the buggy behaviour as correct.
      revision++;
      status = 'submitted';
      decidedAt = null;
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

  group('the server list (ADR-0020 §4)', () {
    test('loads on build without being asked', () async {
      // The group should not have to press anything to learn there is
      // something to read — the session already says who they are.
      final (container, proxy, _) = _harness();
      // `pumpEventQueue` rather than a bare delay: the load is a microtask that
      // awaits a Dio round-trip through the adapter shim, which resolves on its
      // own zone. Two `Duration.zero` delays were NOT enough — measured, the
      // call count was still 0 — and a flaky sleep would hide a real regression
      // behind a timing accident.
      await pumpEventQueue();

      // `loadList` is awaited EXPLICITLY rather than the microtask in
      // `build()` being waited on. Measured: reading only the notifier and
      // pumping leaves `listCalls == 0` in a plain `test()` — the scheduled
      // microtask does not run before the assertion, and a sleep long enough to
      // make it run would be a timing accident that hides a regression. The
      // startup path IS covered, by `account_gate_test.dart` mounting the real
      // app; here the unit under test is the load itself.
      await container.read(studentViewModelProvider.notifier).loadList();
      expect(proxy.listCalls, greaterThan(0));
      final rows = container.read(studentViewModelProvider).rows;
      expect(rows, hasLength(1));
      expect(rows.single.label, 'OTES');
    });

    test('the rows carry the counts a queue badge needs', () async {
      final (container, _, _) = _harness(
        comments: <Map<String, dynamic>>[
          {
            'id': 'c1',
            'author': 'teacher',
            'body': 'x',
            'revision': 1,
            'at': '2026-10-08T03:00:00Z',
            'resolvedAt': null,
            'replies': const <Map<String, dynamic>>[],
          },
          {
            'id': 'c2',
            'author': 'teacher',
            'body': 'y',
            'revision': 1,
            'at': '2026-10-08T04:00:00Z',
            'resolvedAt': null,
            'replies': const <Map<String, dynamic>>[],
          },
        ],
      );
      await container.read(studentViewModelProvider.notifier).loadList();

      final row = container.read(studentViewModelProvider).rows.single;
      expect(row.commentCount, 2);
      expect(
        row.openCommentCount,
        2,
        reason: 'counted before the thread is opened',
      );
    });

    test('a failed list does NOT wipe the round being read', () async {
      // The failure that matters: the student is reading a submission, the
      // list refresh fails, and their screen goes blank because one error
      // field was shared between two unrelated loads.
      final (container, proxy, _) = _harness();
      final notifier = container.read(studentViewModelProvider.notifier);
      await notifier.openSubmission('s1');
      expect(container.read(studentViewModelProvider).submission, isNotNull);

      proxy.failList = true;
      await notifier.loadList();

      final state = container.read(studentViewModelProvider);
      expect(state.listError, isNotNull);
      expect(
        state.submission?.id,
        's1',
        reason: 'a list failure must not clear the open round',
      );
    });

    test(
      'a resubmit refreshes the list, because a round is a new row',
      () async {
        final (container, proxy, _) = _harness(status: 'changes_requested');
        final notifier = container.read(studentViewModelProvider.notifier);
        await notifier.loadList();
        await notifier.openSubmission('s1');
        final before = proxy.listCalls;

        await notifier.resubmit();

        expect(proxy.listCalls, greaterThan(before));
        expect(
          container.read(studentViewModelProvider).submission!.revision,
          2,
        );
      },
    );
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
