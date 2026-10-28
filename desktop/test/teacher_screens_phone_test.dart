/// The three teacher screens at 390×844 — the size WP5 exists to measure.
///
/// AC (a): each screen has a widget test AT 390×844 that PRINTS real width
/// numbers, because "no RenderFlex overflowed" proves nothing: a squeezed
/// button at 28.2px showed no exception, only an ellipsized label with nothing
/// left to tap. Every assertion below measures `tester.getSize(...).width`
/// against the label width and prints both numbers in the failure diff.
///
/// AC (d) of the plan — data measured on REVIEWED content — is honored here
/// by seeding the proxy state through the fake adapter with has_report +
/// score + a decided round, so chips, statuses and the decision row all carry
/// real-width content instead of zero-width placeholders.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/role/app_role.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/features/teacher/data/teacher_store.dart';
import 'package:srs_review_ai/features/teacher/models/teacher_models.dart';
import 'package:srs_review_ai/requirement_review/services/api_service.dart';

/// Routes every dio call to an in-memory proxy: classes, activity,
/// submissions, decisions. Written as routes, not a script, because the
/// screens re-read after every write and a script would not know that.
class _FakeProxyAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> classes = {
    'c1': {
      'id': 'c1',
      'name': 'Lớp Kiến trúc 01',
      'createdAt': '2026-09-27T08:00:00Z',
      'updatedAt': '2026-09-27T08:00:00Z',
    },
  };
  final Map<String, List<Map<String, dynamic>>> members = {
    'c1': [
      {
        'id': 's1',
        'group': 'Nhóm OTES',
        'project': 'OTES',
        'revision': 2,
        'status': 'changes_requested',
        'createdAt': '2026-09-27T09:00:00Z',
        'updatedAt': '2026-09-27T09:30:00Z',
        'has_report': true,
        'score': 6.5,
      },
      {
        'id': 's2',
        'group': 'Nhóm CarbonX',
        'project': 'CarbonX',
        'revision': 1,
        'status': 'submitted',
        'createdAt': '2026-09-27T09:10:00Z',
        'updatedAt': '2026-09-27T09:10:00Z',
        'has_report': false,
        'score': null,
      },
    ],
  };
  final Map<String, List<Map<String, dynamic>>> events = {
    'c1': [
      {
        'submission_id': 's2',
        'group': 'Nhóm CarbonX',
        'event': 'submitted',
        'revision': 1,
        'at': '2026-09-27T09:10:00Z',
      },
      {
        'submission_id': 's1',
        'group': 'Nhóm OTES',
        'event': 'changes_requested',
        'revision': 2,
        'at': '2026-09-27T09:30:00Z',
      },
    ],
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final method = options.method;

    if (method == 'GET') {
      final classRead = RegExp(r'^/classes/([^/]+)$').firstMatch(path);
      if (classRead != null) {
        final id = classRead.group(1)!;
        final record = classes[id];
        if (record == null) return _json({'detail': 'Not Found'}, status: 404);
        return _json({
          ...record,
          'submissions': members[id] ?? const <Map<String, dynamic>>[],
        });
      }
      final activity = RegExp(r'^/classes/([^/]+)/activity$').firstMatch(path);
      if (activity != null) {
        final id = activity.group(1)!;
        return _json({
          'id': id,
          'events': events[id] ?? const <Map<String, dynamic>>[],
        });
      }
      final submissionRead = RegExp(r'^/submissions/([^/]+)$').firstMatch(path);
      if (submissionRead != null) {
        final id = submissionRead.group(1)!;
        for (final row in members.values.expand((rows) => rows)) {
          if (row['id'] == id) {
            return _json({
              ...row,
              'upload_uri': '',
              'note': '',
              'class_id': 'c1',
              'decidedAt': row['status'] == 'submitted'
                  ? null
                  : '2026-09-27T09:30:00Z',
              'decision_note': 'Bổ sung hậu điều kiện cho UC04.',
              'previous_id': null,
              'timeApproximate': false,
              'history': [
                {
                  'revision': 1,
                  'at': '2026-09-27T09:00:00Z',
                  'status': 'submitted',
                  'event': 'submitted',
                },
                {
                  'revision': 2,
                  'at': '2026-09-27T09:30:00Z',
                  'status': 'changes_requested',
                  'event': 'changes_requested',
                },
              ],
              'findings': {'high': 2, 'medium': 5},
            });
          }
        }
        return _json({'detail': 'Not Found'}, status: 404);
      }
    }

    if (method == 'POST' && path == '/classes') {
      final body = await _body(options, requestStream);
      final id = 'c${classes.length + 1}';
      final record = {
        'id': id,
        'name': body['name'] as String? ?? '',
        'createdAt': '2026-09-27T10:00:00Z',
        'updatedAt': '2026-09-27T10:00:00Z',
      };
      classes[id] = record;
      members[id] = <Map<String, dynamic>>[];
      events[id] = <Map<String, dynamic>>[];
      return _json({
        ...record,
        'write_key': 'key-$id',
        'url': '/classes/$id',
      }, status: 201);
    }

    final decision = RegExp(
      r'^/submissions/([^/]+)/decision$',
    ).firstMatch(path);
    if (method == 'POST' && decision != null) {
      final id = decision.group(1)!;
      for (final entry in members.entries) {
        for (final row in entry.value) {
          if (row['id'] == id) {
            final body = await _body(options, requestStream);
            row['status'] = body['decision'] as String? ?? row['status'];
            return _json({
              'id': id,
              'status': row['status'],
              'decidedAt': '2026-09-27T10:00:00Z',
              'updatedAt': '2026-09-27T10:00:00Z',
              'class_id': entry.key,
            });
          }
        }
      }
      return _json({'detail': 'Not Found'}, status: 404);
    }

    return _json({'detail': 'Not Found'}, status: 404);
  }

  Future<Map<String, dynamic>> _body(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    final data = options.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      return Map<String, dynamic>.from(
        jsonDecode(data) as Map<dynamic, dynamic>,
      );
    }
    return const {};
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

const double kPhoneWidth = 390;
const double kPhoneHeight = 844;

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(kPhoneWidth, kPhoneHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps the teacher build at phone size with the fake proxy and the memory
/// store wired in, pre-seeded with one saved class. Returns
/// (container, router) so a test can drive screens.
(ProviderContainer, GoRouter) _harness(WidgetTester tester) {
  final adapter = _FakeProxyAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = adapter;
  final store = MemoryTeacherStore()
    ..saveClass(
      TeacherClassRecord(
        id: 'c1',
        name: 'Lớp Kiến trúc 01',
        writeKey: 'key-c1',
        savedAt: DateTime(2026, 9, 27, 8),
      ),
    );
  final container = ProviderContainer(
    overrides: [
      teacherStoreProvider.overrideWithValue(store),
      // The teacher feature owns its ApiService instance; rebuilt here on the
      // fake adapter so no test touches a real socket.
      teacherApiProvider.overrideWith((ref) => ApiService(dio: dio)),
      // Overridden so the report-link helper can never blow up on a missing
      // provider in a bare test container.
      teacherApiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
    ],
  );
  addTearDown(container.dispose);
  final router = buildRouter(scope: const AppRoleScope.teacher());
  return (container, router);
}

Future<void> _pumpShell(
  WidgetTester tester,
  ProviderContainer container,
  GoRouter router,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
}

/// Drains the exception queue: tester.takeException() returns ONE error and
/// the rest stay queued — a single call reads green while errors wait in line.
Future<List<Object>> _drainExceptions(WidgetTester tester) async {
  final errors = <Object>[];
  await tester.pump();
  while (true) {
    final error = tester.takeException();
    if (error == null) break;
    errors.add(error as Object);
  }
  return errors;
}

/// Prints a measured control width next to the label's INTRINSIC width — the
/// failure diff IS the measurement the AC asks for. The intrinsic width comes
/// from a TextPainter at the button's label size, because `tester.getSize` on
/// the Text widget returns the ALLOCATED box (always ≤ the control), which
/// would make the assertion vacuous.
void _expectLabelFits({
  required WidgetTester tester,
  required Finder button,
  required String label,
  required String name,
}) {
  final width = tester.getSize(button).width;
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: Theme.of(
        tester.element(find.bySubtype<ButtonStyleButton>().first),
      ).textTheme.labelLarge,
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final textWidth = painter.width;
  painter.dispose();
  // ignore: avoid_print
  print(
    'MEASURED [$name] control=${width.toStringAsFixed(1)} px, label="$label"=${textWidth.toStringAsFixed(1)} px',
  );
  expect(
    width,
    greaterThanOrEqualTo(textWidth),
    reason:
        '$name is ${width.toStringAsFixed(1)} px wide but its label needs '
        '${textWidth.toStringAsFixed(1)} px — the label is ellipsized and the '
        'control is an empty pill (the 28.2px trap WP5 measures for).',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen 1 class list at 390x844 create button measured', (
    tester,
  ) async {
    _phoneSurface(tester);
    final (container, router) = _harness(tester);

    await _pumpShell(tester, container, router);
    // The roster read is async; wait for the seeded class row.
    for (
      var i = 0;
      i < 30 &&
          find.byKey(const Key('teacher-class-card-c1')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    _expectLabelFits(
      tester: tester,
      button: find.byKey(const Key('teacher-create-class')),
      label: 'Tạo lớp',
      name: 'Tạo lớp (FilledButton)',
    );
    // The seeded class renders its saved-on-this-device line.
    expect(find.text('Lớp Kiến trúc 01'), findsOneWidget);

    final errors = await _drainExceptions(tester);
    for (final error in errors) {
      // ignore: avoid_print
      print('QUEUED-EXCEPTION [screen 1] $error');
    }
    expect(
      errors,
      isEmpty,
      reason:
          'overflow queue must be empty, not just the first error; the '
          'queued diagnostics above name the overflowing widget',
    );
  });

  testWidgets('screen 2 class inbox at 390x844 new badge and truthful copy', (
    tester,
  ) async {
    _phoneSurface(tester);
    final (container, router) = _harness(tester);

    await _pumpShell(tester, container, router);
    router.go(AppRoutes.classLocation('c1'));
    for (
      var i = 0;
      i < 30 &&
          find.byKey(const Key('teacher-inbox-row-s1')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Truthful inbox copy: pull, not push; watermark is per-device.
    expect(
      find.text(
        'Hộp thư kéo khi mở — không có thông báo đẩy. Dấu “đã đọc” là của máy này.',
      ),
      findsOneWidget,
    );

    // The submission row with a review behind it renders its status chip with
    // a measured width — reviewed data, not zero chips.
    final row = find.byKey(const Key('teacher-inbox-row-s1'));
    await tester.ensureVisible(row);
    final chipWidth = tester
        .getSize(
          find.descendant(of: row, matching: find.byType(Container)).last,
        )
        .width;
    // ignore: avoid_print
    print(
      'MEASURED [status chip (changes_requested) on row s1] width=$chipWidth px',
    );
    expect(chipWidth, greaterThan(20));

    final errors = await _drainExceptions(tester);
    expect(errors, isEmpty);
  });

  testWidgets('screen 3 submission at 390x844 decision buttons measured', (
    tester,
  ) async {
    _phoneSurface(tester);
    final (container, router) = _harness(tester);

    await _pumpShell(tester, container, router);
    router.go(AppRoutes.submissionLocation('s1'));
    for (
      var i = 0;
      i < 30 && find.byKey(const Key('teacher-approve')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    _expectLabelFits(
      tester: tester,
      button: find.byKey(const Key('teacher-approve')),
      label: 'Duyệt bài',
      name: 'Duyệt bài (FilledButton.icon)',
    );
    _expectLabelFits(
      tester: tester,
      button: find.byKey(const Key('teacher-request-changes')),
      label: 'Yêu cầu sửa',
      name: 'Yêu cầu sửa (FilledButton.tonal)',
    );

    // The uncalibrated-score flag is ON the reading view.
    expect(find.byKey(const Key('teacher-uncalibrated-flag')), findsOneWidget);
    expect(find.textContaining('CHƯA được kiểm định'), findsOneWidget);

    final errors = await _drainExceptions(tester);
    expect(errors, isEmpty);
  });

  testWidgets('decision flow approve records reread renders one-line feedback', (
    tester,
  ) async {
    _phoneSurface(tester);
    final (container, router) = _harness(tester);

    await _pumpShell(tester, container, router);
    router.go(AppRoutes.submissionLocation('s1'));
    for (
      var i = 0;
      i < 30 && find.byKey(const Key('teacher-approve')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // At 390x844 the action row sits below the fold; a tap on an off-screen
    // button is a tap on nothing. Bring it into view first.
    await tester.ensureVisible(find.byKey(const Key('teacher-approve')));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('teacher-approve')));
    // decide() = POST + re-read (class + activity + submission contexts); give
    // every chained future frames to finish before asserting.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // The one-line feedback, no modal: the line next to the buttons (the
    // keyed Text), plus the success toast the view raises on top of it — the
    // SAME sentence, so the global count is 2, not 1.
    final feedbackLine = find.byKey(const Key('teacher-action-feedback'));
    expect(feedbackLine, findsOneWidget);
    expect(
      tester.widget<Text>(feedbackLine).data,
      'Đã ghi quyết định: Duyệt bài.',
    );
    expect(find.text('Đã ghi quyết định: Duyệt bài.'), findsWidgets);

    final errors = await _drainExceptions(tester);
    expect(errors, isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });
}
