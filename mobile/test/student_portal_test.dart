import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/features/student/data/my_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/my_submissions_view.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_home_screen.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_upload_screen.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';
import 'package:srs_review_ai_mobile/theme/app_theme.dart';
import 'package:srs_review_ai_mobile/widgets/app_scaffold.dart';

import 'support/academic_fixture.dart';

class _Subs implements MySubmissionsRepository {
  _Subs(this.items);
  final List<MySubmission> items;
  String? askedFor;
  @override
  Stream<List<MySubmission>> watch(String uid) {
    askedFor = uid;
    return Stream.value(items);
  }
}

class _Inbox implements PushInboxRepository {
  _Inbox(this.items);
  List<PushInboxItem> items;
  final read = <String>[];
  @override
  Stream<List<PushInboxItem>> watch(String uid) => Stream.value(items);
  @override
  Future<void> record(String uid, String id, Map<String, Object?> f) async {}
  @override
  Future<void> markRead(String uid, String id) async => read.add(id);
}

final _items = [
  MySubmission(
    id: 'a',
    fileName: 'srs-v2.pdf',
    fileUrl: 'https://res.cloudinary.com/demo/image/upload/a.pdf',
    uploadedAt: DateTime(2026, 11, 10, 9),
    decision: 'needsRevision',
    decisionReason: 'Thiếu sơ đồ use case cho phân hệ điểm danh.',
  ),
  MySubmission(
    id: 'b',
    fileName: 'srs-v1.pdf',
    fileUrl: 'https://res.cloudinary.com/demo/image/upload/b.pdf',
    uploadedAt: DateTime(2026, 11, 9, 9),
    status: 'reviewing',
  ),
];

const _note = PushInboxItem(
  id: 'n1',
  title: 'Giảng viên đang chấm bài của bạn',
  body: 'srs-v1.pdf',
  type: 'submission_status',
  targetId: 'b',
);

Future<(_Subs, _Inbox, List<String>)> _mount(
  WidgetTester t,
  Size size, {
  List<MySubmission>? items,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final subs = _Subs(items ?? _items);
  final inbox = _Inbox([_note]);
  final opened = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        mySubmissionsRepositoryProvider.overrideWithValue(subs),
        pushInboxRepositoryProvider.overrideWithValue(inbox),
        pushInboxUidProvider.overrideWith((ref) => Stream.value('sv1')),
        studentAcademicSnapshotProvider.overrideWith(
          (ref) => Stream.value(academicFixture()),
        ),
        remoteConfigValuesProvider.overrideWith(
          (ref) => Stream.value(const RemoteConfigValues()),
        ),
        mySubmissionOpenerProvider.overrideWithValue(
          (context, ref, s) async => opened.add(s.id),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const StudentHomeScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (subs, inbox, opened);
}

List<Object> _drain(WidgetTester t) {
  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  return errors;
}

void main() {
  group('trạng thái bài nộp', () {
    test('không có field nào → Đã nộp', () {
      const s = MySubmission(id: 'x', fileName: 'a', fileUrl: '');
      expect(s.stage, SubmissionStage.submitted);
      expect(s.stageLabel, 'Đã nộp');
    });
    test('queued vẫn là bước 1 nhưng nhãn nói rõ', () {
      const s = MySubmission(
        id: 'x',
        fileName: 'a',
        fileUrl: '',
        status: 'queued',
      );
      expect(s.stage, SubmissionStage.submitted);
      expect(s.stageLabel, 'Đã vào hàng chờ');
    });
    test('server chỉ ghi decision (không có status) vẫn là có kết quả', () {
      const s = MySubmission(
        id: 'x',
        fileName: 'a',
        fileUrl: '',
        decision: 'approved',
      );
      expect(s.stage, SubmissionStage.done);
      expect(s.stageLabel, 'Đạt');
      expect(s.tone, 'brand');
    });
    test('decision lạ không bị coi là kết quả', () {
      const s = MySubmission(
        id: 'x',
        fileName: 'a',
        fileUrl: '',
        decision: 'hack',
      );
      expect(s.stage, SubmissionStage.submitted);
    });
    test('link ngoài Cloudinary https không được mở', () {
      const s = MySubmission(
        id: 'x',
        fileName: 'a',
        fileUrl: 'http://evil.example/a.pdf',
      );
      expect(s.safeUrl, isNull);
    });
    test('bài vừa nộp (chưa có giờ server) lên đầu', () {
      final sorted = sortNewestFirst([
        MySubmission(
          id: 'old',
          fileName: '',
          fileUrl: '',
          uploadedAt: DateTime(2026),
        ),
        const MySubmission(id: 'new', fileName: '', fileUrl: ''),
      ]);
      expect(sorted.map((s) => s.id), ['new', 'old']);
    });
  });

  testWidgets('390 dp: tab dưới, xem bài của mình kèm nhận xét', (t) async {
    final (subs, _, opened) = await _mount(t, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.text('Nộp tài liệu SRS'), findsOneWidget);

    await t.tap(find.text('Bài của tôi').last);
    await t.pumpAndSettle();
    // Truy vấn đúng người đăng nhập (rules chặn truy vấn không lọc).
    expect(subs.askedFor, 'sv1');
    expect(find.text('Cần chỉnh sửa'), findsOneWidget);
    expect(find.text('Đang chấm'), findsWidgets);
    expect(
      find.text('Thiếu sơ đồ use case cho phân hệ điểm danh.'),
      findsOneWidget,
    );
    await t.tap(find.text('Xem tệp').first);
    await t.pump();
    expect(opened, ['a']);
    expect(_drain(t), isEmpty);
  });

  testWidgets('bấm thông báo bài nộp: đánh dấu đã đọc và mở Bài của tôi', (
    t,
  ) async {
    final (_, inbox, _) = await _mount(t, const Size(390, 844));
    // Badge chưa đọc trên tab Thông báo.
    expect(find.text('1'), findsOneWidget);
    await t.tap(find.text('Thông báo').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Giảng viên đang chấm bài của bạn'));
    await t.pumpAndSettle();
    expect(inbox.read, ['n1']);
    expect(find.text('Thiếu sơ đồ use case cho phân hệ điểm danh.'), findsOne);
    expect(_drain(t), isEmpty);
  });

  testWidgets('chưa nộp bài nào: trạng thái rỗng có nút dẫn về Nộp bài', (
    t,
  ) async {
    await _mount(t, const Size(390, 844), items: const []);
    await t.tap(find.text('Bài của tôi').last);
    await t.pumpAndSettle();
    expect(find.text('Bạn chưa nộp bài nào'), findsOneWidget);
    await t.tap(find.widgetWithText(InkWell, 'Nộp tài liệu').last);
    await t.pumpAndSettle();
    expect(find.text('Nộp tài liệu SRS'), findsOneWidget);
    expect(_drain(t), isEmpty);
  });

  for (final width in [1024.0, 1440.0]) {
    testWidgets('$width dp: sidebar sinh viên, không có menu giảng viên', (
      t,
    ) async {
      await _mount(t, Size(width, 900));
      final sidebar = find.byType(DesktopSidebar);
      expect(sidebar, findsOneWidget);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      for (final label in [
        'Nộp bài',
        'Bài của tôi',
        'Thông báo',
        'Đăng xuất',
      ]) {
        expect(
          find.descendant(of: sidebar, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('Lớp học'), findsNothing);
      expect(find.text('Yêu cầu đánh giá'), findsNothing);

      await t.tap(
        find.descendant(of: sidebar, matching: find.text('Bài của tôi')),
      );
      await t.pumpAndSettle();
      expect(find.text('srs-v2.pdf'), findsOneWidget);
      // Nút "Xem tệp" không bị bóp cạn (lỗi Expanded không ném overflow).
      expect(t.getSize(find.text('Xem tệp').first).width, greaterThan(40));
      expect(_drain(t), isEmpty);
    });
  }

  testWidgets('nút hộp thư trên top bar mở tab Thông báo', (t) async {
    await _mount(t, const Size(1440, 900));
    await t.tap(find.byTooltip('Thông báo (1 chưa đọc)'));
    await t.pumpAndSettle();
    expect(find.text('Giảng viên đang chấm bài của bạn'), findsOneWidget);
    expect(_drain(t), isEmpty);
  });
}
