/// The student screen and the route that reaches it.
///
/// Two things are pinned here that a view-model test cannot see:
///
/// * **The button is absent, not merely disabled, before the teacher returns
///   the round** — a disabled control implies "you could, but not yet", which
///   is a different promise than "there is nothing to do here".
/// * **The screen is reached through the real router**, at the position the
///   shell's `goBranch(i)` uses. The trap this avoids is the one
///   `review_history_route_test.dart` already paid for: a destination added at
///   index N while the route sits elsewhere lands silently on the wrong
///   screen, and only a navigation test through `StatefulNavigationShell`
///   catches it — asserting a path literal would pass while the app is broken.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/role/app_role.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/features/student/data/student_repository.dart';
import 'package:srs_review_ai/features/student/data/student_store.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shell.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

/// A proxy that serves one submission and its thread.
class _Proxy implements HttpClientAdapter {
  _Proxy({required this.status, this.comments = const []});

  final String status;
  final List<Map<String, dynamic>> comments;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final row = {
      'id': 's1',
      'group': 'Nhóm OTES',
      'project': 'OTES',
      'revision': 1,
      'status': status,
      'decidedAt': '2026-10-08T02:00:00Z',
      'decision_note': 'Sửa mục 3.2 rồi nộp lại nhé.',
      'createdAt': '2026-10-08T01:00:00Z',
      'updatedAt': '2026-10-08T02:00:00Z',
      'history': const <Map<String, dynamic>>[],
      'comments': comments,
      'has_report': false,
      'score': 6.5,
    };
    return ResponseBody.fromString(
      jsonEncode(row),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(ProviderContainer, MemoryStudentStore) _harness({
  required String status,
  List<Map<String, dynamic>> comments = const [],
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = _Proxy(status: status, comments: comments);
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
  return (container, store);
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: buildRouter(scope: const AppRoleScope.student()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
}

/// Drives to the feedback destination the way the shell does — by BRANCH
/// INDEX, not by path — so an index/route mismatch fails this test.
Future<void> _goToFeedback(WidgetTester tester) async {
  final shell = tester.widget<WorkspaceShell>(find.byType(WorkspaceShell));
  shell.navigationShell.goBranch(4);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Pumps a few FIXED frames instead of `pumpAndSettle`.
///
/// `pumpAndSettle` never returns while a `CircularProgressIndicator` is on
/// screen — it animates forever, so "settled" never arrives and the test hangs
/// until the 10-minute timeout. Fixed pumps advance past the async load
/// without waiting for an animation that by design never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    // Phone size: the brief's target, and the width the action row was
    // measured at in the teacher screens.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('branch 4 lands on "Phản hồi từ giáo viên"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (container, _) = _harness(status: 'changes_requested');
    await _pump(tester, container);
    await _goToFeedback(tester);

    // The destination exists AND the route it maps to is the student screen —
    // not, say, the report screen one index away.
    expect(find.text('Phản hồi từ giáo viên'), findsWidgets);
    expect(
      tester
          .widget<WorkspaceShell>(find.byType(WorkspaceShell))
          .navigationShell
          .currentIndex,
      4,
    );
  });

  testWidgets('no resubmit button while the round waits for the teacher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (container, _) = _harness(status: 'submitted');
    await _pump(tester, container);
    await _goToFeedback(tester);
    // `runAsync` is required, not cosmetic: `testWidgets` runs on a fake clock,
    // so `await` on a REAL I/O future (dio's adapter) never completes — the
    // test hangs to the 10-minute timeout with no error anywhere. `runAsync`
    // lets the real event loop turn while the read is in flight.
    await tester.runAsync(
      () => container
          .read(studentViewModelProvider.notifier)
          .openSubmission('s1'),
    );
    await _settle(tester);

    expect(find.byKey(const Key('resubmit-button')), findsNothing);
    // And the screen SAYS why, so a hidden button is not a dead end.
    expect(find.byKey(const Key('resubmit-hint')), findsOneWidget);
    expect(find.textContaining('Chờ giáo viên phản hồi'), findsOneWidget);
  });

  testWidgets('changes_requested shows the button and the note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (container, _) = _harness(status: 'changes_requested');
    await _pump(tester, container);
    await _goToFeedback(tester);
    // `runAsync` is required, not cosmetic: `testWidgets` runs on a fake clock,
    // so `await` on a REAL I/O future (dio's adapter) never completes — the
    // test hangs to the 10-minute timeout with no error anywhere. `runAsync`
    // lets the real event loop turn while the read is in flight.
    await tester.runAsync(
      () => container
          .read(studentViewModelProvider.notifier)
          .openSubmission('s1'),
    );
    await _settle(tester);

    expect(find.byKey(const Key('resubmit-button')), findsOneWidget);
    expect(find.byKey(const Key('resubmit-hint')), findsNothing);
    // The teacher's note is the reason the group is here — it must be visible
    // in full, not truncated behind an expander.
    expect(find.text('Sửa mục 3.2 rồi nộp lại nhé.'), findsOneWidget);
  });

  testWidgets('a teacher remark and the group reply both render', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (container, _) = _harness(
      status: 'changes_requested',
      comments: [
        {
          'id': 'c0',
          'author': 'teacher',
          'body': 'Sửa mục 3.2',
          'revision': 1,
          'at': '2026-10-08T02:00:00Z',
          'resolvedAt': null,
          'replies': [
            {
              'id': 'r0',
              'author': 'student',
              'body': 'Dạ em sửa rồi ạ',
              'revision': 1,
              'at': '2026-10-08T02:30:00Z',
              'replyTo': 'c0',
              'resolvedAt': null,
            },
          ],
        },
      ],
    );
    await _pump(tester, container);
    await _goToFeedback(tester);
    // `runAsync` is required, not cosmetic: `testWidgets` runs on a fake clock,
    // so `await` on a REAL I/O future (dio's adapter) never completes — the
    // test hangs to the 10-minute timeout with no error anywhere. `runAsync`
    // lets the real event loop turn while the read is in flight.
    await tester.runAsync(
      () => container
          .read(studentViewModelProvider.notifier)
          .openSubmission('s1'),
    );
    await _settle(tester);

    expect(find.text('Sửa mục 3.2'), findsOneWidget);
    expect(find.text('Dạ em sửa rồi ạ'), findsOneWidget);
  });

  testWidgets('the screen does not overflow at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (container, _) = _harness(status: 'changes_requested');
    await _pump(tester, container);
    await _goToFeedback(tester);
    // `runAsync` is required, not cosmetic: `testWidgets` runs on a fake clock,
    // so `await` on a REAL I/O future (dio's adapter) never completes — the
    // test hangs to the 10-minute timeout with no error anywhere. `runAsync`
    // lets the real event loop turn while the read is in flight.
    await tester.runAsync(
      () => container
          .read(studentViewModelProvider.notifier)
          .openSubmission('s1'),
    );
    await _settle(tester);

    // Drain the exception queue rather than reading one: RenderFlex overflow
    // throws once per frame and a single takeException() would read green.
    await tester.pump();
    final errors = <Object>[];
    while (true) {
      final error = tester.takeException();
      if (error == null) break;
      errors.add(error as Object);
    }
    expect(errors, isEmpty, reason: 'errors waiting in the queue: $errors');
  });
}
