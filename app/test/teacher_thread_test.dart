/// The teacher's thread view-model — over a fake proxy that ACTUALLY checks
/// the class key.
///
/// The single most important thing pinned here: the write key is really sent.
/// A teacher's authority on this route IS the key (`X-Class-Key`), so a
/// view-model that forgot it would be green against a permissive fake and
/// answer 409 in production. The fake therefore refuses any write without the
/// right key — the failure mode is reproduced, not assumed — and one test
/// removes the class from the store to prove the refusal path is reached.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/features/teacher/data/teacher_store.dart';
import 'package:srs_review_ai/features/teacher/models/teacher_models.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

const String _kClassId = 'c1';
const String _kWriteKey = 'key-c1';
const String _kSubmission = 's1';

/// Serves the teacher's reads and the comment writes, and GATES the writes on
/// `X-Class-Key` exactly as the store does.
class _GatedProxy implements HttpClientAdapter {
  /// The key the proxy accepts — the store's value. Any other key (or none)
  /// makes every write fail with 409, which is the store's real behaviour and
  /// the reason a view-model that dropped the key cannot pass this file.
  static const String acceptKey = _kWriteKey;

  /// Whether this fake sees a signed-in session on the request.
  ///
  /// The server has TWO ways into these writes and the fake has to model both,
  /// or it tests a server that does not exist. With a session the server takes
  /// the teacher's class off the session and never looks for a key (ADR-0021);
  /// without one the key is the only way in and its absence is a 409.
  ///
  /// Modelled as a flag rather than by sniffing a Cookie header because the
  /// cookie is attached by the Dio interceptor, one layer above this adapter —
  /// the fake would be asserting on plumbing it cannot see, which is how a
  /// fake starts agreeing with whatever the code happens to do.
  bool signedIn = false;

  final List<Map<String, dynamic>> comments = [];
  int nextId = 0;
  final List<String> rejectedWrites = [];

  Map<String, dynamic> _row() => {
    'id': _kSubmission,
    'group': 'Nhóm OTES',
    'project': 'OTES',
    'revision': 1,
    'status': 'submitted',
    'class_id': _kClassId,
    'decidedAt': null,
    'decision_note': '',
    'createdAt': '2026-10-08T01:00:00Z',
    'updatedAt': '2026-10-08T02:00:00Z',
    'history': const <Map<String, dynamic>>[],
    'comments': comments,
    'has_report': true,
    'score': 6.5,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final method = options.method.toUpperCase();

    if (method == 'GET') {
      if (path == '/classes') return _json(const <Map<String, dynamic>>[]);
      if (path.startsWith('/classes/')) {
        return _json({
          'class': {
            'id': _kClassId,
            'name': 'Lớp Kiến trúc 01',
            'createdAt': '2026-10-08T00:00:00Z',
            'updatedAt': '2026-10-08T00:00:00Z',
          },
          'submissions': [_row()],
        });
      }
      if (path.startsWith('/submissions/')) return _json(_row());
      return _json(const <Map<String, dynamic>>[]);
    }

    // A write. The gate is the point of the fake.
    final presented = options.headers['X-Class-Key'];
    final authorised = presented == acceptKey || signedIn;
    if (!authorised) {
      rejectedWrites.add('$method $path');
      return _json({'detail': 'not_in_class'}, status: 409);
    }

    if (method == 'POST' && path.endsWith('/comments')) {
      final body = options.data as Map<String, dynamic>;
      comments.add({
        'id': 'c$nextId',
        'author': body['author'],
        'body': body['body'],
        'revision': 1,
        'at': '2026-10-08T0$nextId:00:00Z',
        'resolvedAt': null,
      });
      nextId++;
      return _json(comments.last, status: 201);
    }
    if (method == 'POST' && path.endsWith('/replies')) {
      final body = options.data as Map<String, dynamic>;
      // /submissions/<id>/comments/<cid>/replies -> cid at index 4.
      final parentId = path.split('/')[4];
      final target = comments.firstWhere((c) => c['id'] == parentId);
      final replies = (target['replies'] as List<dynamic>? ?? <dynamic>[]);
      replies.add({
        'id': 'r$nextId',
        'author': body['author'],
        'body': body['body'],
        'revision': 1,
        'at': '2026-10-08T0$nextId:00:00Z',
        'replyTo': parentId,
        'resolvedAt': null,
      });
      nextId++;
      target['replies'] = replies;
      return _json(replies.last, status: 201);
    }
    if (method == 'PATCH') {
      final body = options.data as Map<String, dynamic>;
      final cid = path.split('/')[4];
      final target = comments.firstWhere((c) => c['id'] == cid);
      target['resolvedAt'] = body['resolved'] == true
          ? '2026-10-08T05:00:00Z'
          : null;
      return _json(target);
    }
    return _json({'detail': 'not found'}, status: 404);
  }

  ResponseBody _json(Object? body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

(ProviderContainer, _GatedProxy) _harness({
  bool keyOnDevice = true,
  bool signedIn = false,
}) {
  final proxy = _GatedProxy()..signedIn = signedIn;
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = proxy;
  final store = MemoryTeacherStore();
  if (keyOnDevice) {
    store.saveClass(
      TeacherClassRecord(
        id: _kClassId,
        name: 'Lớp Kiến trúc 01',
        writeKey: _kWriteKey,
        savedAt: DateTime(2026, 10, 8, 8),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      teacherStoreProvider.overrideWithValue(store),
      teacherApiProvider.overrideWith((ref) => ApiService(dio: dio)),
      teacherApiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
    ],
  );
  addTearDown(container.dispose);
  return (container, proxy);
}

void main() {
  test('a teacher comment is written with the class key', () async {
    final (container, proxy) = _harness();
    final vm = container.read(teacherViewModelProvider.notifier);
    // The real landing screen loads the roster before opening a submission —
    // the write key lives on that record, so skipping this is not a shortcut.
    await vm.loadSavedClasses();
    await vm.openSubmission(_kSubmission);
    await vm.addComment(_kSubmission, 'Mục 3.2 thiếu hậu điều kiện.');

    expect(
      proxy.rejectedWrites,
      isEmpty,
      reason: 'the write key did not reach the proxy',
    );
    expect(proxy.comments, hasLength(1));
    expect(proxy.comments.single['author'], 'teacher');
    // And the thread the view renders comes from the READ, not the write.
    final detail = container.read(teacherViewModelProvider).detail!;
    expect(detail.comments, hasLength(1));
    expect(detail.comments.single.body, 'Mục 3.2 thiếu hậu điều kiện.');
  });

  test('with no key but a session, the write goes through', () async {
    // ADR-0021 changed what "no key on this device" MEANS. It used to mean
    // "you cannot write" and this test used to assert exactly that. It now
    // means "send what you have and let the session speak" — a teacher who
    // signed in on a new device, with no saved class on it, was previously
    // told to open a class the server already knew they owned.
    final (container, proxy) = _harness(keyOnDevice: false, signedIn: true);
    final vm = container.read(teacherViewModelProvider.notifier);
    await vm.loadSavedClasses();
    await vm.openSubmission(_kSubmission);
    await vm.addComment(_kSubmission, 'Thử khi thiếu key nhưng có phiên.');

    expect(proxy.comments, hasLength(1), reason: 'the session should carry it');
    expect(proxy.rejectedWrites, isEmpty);
  });

  test(
    'with neither key nor session, nothing is written and the reason shows',
    () async {
      // The other half, and the one that must not be lost while relaxing the
      // first: no key AND no session is still no authority. The view-model now
      // SENDS the request instead of refusing locally, so the refusal has to
      // come back from the server and reach the teacher as feedback.
      final (container, proxy) = _harness(keyOnDevice: false, signedIn: false);
      final vm = container.read(teacherViewModelProvider.notifier);
      await vm.loadSavedClasses();
      await vm.openSubmission(_kSubmission);
      await vm.addComment(_kSubmission, 'Thử khi không có gì cả.');

      expect(
        proxy.comments,
        isEmpty,
        reason: 'a keyless, sessionless write went through',
      );
      expect(
        proxy.rejectedWrites,
        isNotEmpty,
        reason: 'the server was never asked',
      );
      expect(
        container.read(teacherViewModelProvider).actionFeedback,
        isNotNull,
        reason: 'a refusal the teacher cannot see is a silent failure',
      );
    },
  );

  test('a teacher reply lands under its comment, not as a new one', () async {
    final (container, proxy) = _harness();
    final vm = container.read(teacherViewModelProvider.notifier);
    // The real landing screen loads the roster before opening a submission —
    // the write key lives on that record, so skipping this is not a shortcut.
    await vm.loadSavedClasses();
    await vm.openSubmission(_kSubmission);
    await vm.addComment(_kSubmission, 'Câu hỏi mở');
    final parentId = proxy.comments.single['id'] as String;

    await vm.replyToComment(_kSubmission, parentId, 'Bổ sung giúp cô.');

    expect(proxy.comments, hasLength(1), reason: 'the reply became a comment');
    final detail = container.read(teacherViewModelProvider).detail!;
    expect(detail.comments.single.replies, hasLength(1));
    expect(detail.comments.single.replies.single.author, 'teacher');
  });

  test('resolving a remark is a keyed write and reloads the thread', () async {
    final (container, proxy) = _harness();
    final vm = container.read(teacherViewModelProvider.notifier);
    // The real landing screen loads the roster before opening a submission —
    // the write key lives on that record, so skipping this is not a shortcut.
    await vm.loadSavedClasses();
    await vm.openSubmission(_kSubmission);
    await vm.addComment(_kSubmission, 'Cần sửa');
    final id = proxy.comments.single['id'] as String;

    await vm.setCommentResolved(_kSubmission, id, true);

    expect(proxy.rejectedWrites, isEmpty);
    final detail = container.read(teacherViewModelProvider).detail!;
    expect(detail.comments.single.isResolved, isTrue);
  });

  test(
    'a sessionless reply with no key is refused by the server, not locally',
    () async {
      // What this pins CHANGED with ADR-0021 and the change is deliberate. It
      // used to pin "the view-model refuses before calling the proxy" — a
      // client-side gate. The authority now lives on the server, and a client
      // gate that is the only gate is exactly the shape ADR-0021 exists to
      // remove: the app was deciding who may write, and an app is not a
      // security boundary.
      final (container, proxy) = _harness(keyOnDevice: false, signedIn: false);
      final vm = container.read(teacherViewModelProvider.notifier);
      await vm.loadSavedClasses();
      await vm.openSubmission(_kSubmission);
      await vm.replyToComment(_kSubmission, 'c0', 'x');

      expect(
        proxy.rejectedWrites,
        isNotEmpty,
        reason: 'the server must be the one refusing',
      );
      expect(proxy.comments, isEmpty);
    },
  );
}
