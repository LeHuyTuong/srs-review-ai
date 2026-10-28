import 'package:srs_review_ai_mobile/app/session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/repositories/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/screens/academic/course_screens.dart';
import 'package:srs_review_ai_mobile/screens/academic/class_screens.dart';
import 'package:srs_review_ai_mobile/screens/academic/offering_detail_screen.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/student_enrollment_sheet.dart';
import 'package:srs_review_ai_mobile/theme/app_theme.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';

import 'support/academic_fixture.dart';

const screens = <String, Widget>{
  'Môn học': CourseListScreen(),
  'Chi tiết môn': CourseDetailScreen(courseId: 'swp391'),
  'Đợt học': OfferingDetailScreen(offeringId: 'off-f26-swp391'),
  'Lớp': ClassListScreen(),
  'Chi tiết lớp': ClassDetailScreen(classId: 'se1701'),
  'Bộ quy tắc': RuleSetSelectionScreen(),
};
Future<void> mount(
  WidgetTester tester,
  Widget child,
  AcademicRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSessionProvider.overrideWithValue(
          const AppSession('supervisor'),
        ),
        academicRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
  });
  for (final width in [360.0, 390.0, 412.0]) {
    for (final e in screens.entries) {
      testWidgets('${e.key}: data, không overflow ở $width dp', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 844);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await mount(t, e.value, TestAcademicRepository(academicFixture()));
        expect(find.byType(AppErrorState), findsNothing);
        expect(find.byType(AppLoadingState), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
  for (final e in screens.entries) {
    testWidgets('${e.key}: loading, lỗi và retry', (t) async {
      final repo = _DeferredRepository();
      await mount(t, e.value, repo);
      expect(find.byType(AppLoadingState), findsOneWidget);
      repo.completer.completeError(const AcademicFailure('Không lộ lỗi này'));
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Không lộ lỗi này'), findsNothing);
      repo.completer = Completer<AcademicSnapshot>();
      await t.tap(find.widgetWithText(AppButton, 'Thử lại'));
      await t.pump();
      repo.completer.complete(academicFixture());
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('${e.key}: rỗng/không tìm thấy', (t) async {
      var s = academicFixture();
      for (final key in [
        'courses',
        'offerings',
        'classes',
        'groups',
        'students',
        'ruleSets',
      ]) {
        s = s.replaceCollection(key, []);
      }
      await mount(t, e.value, TestAcademicRepository(s));
      expect(find.byType(AppEmptyState), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Tạo môn qua modal, hủy không ghi; lưu hiện trên danh sách', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(t, const CourseListScreen(), repo);
    await t.tap(find.widgetWithText(AppButton, 'Thêm môn học'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'TST101');
    await t.enterText(find.byType(TextField).at(1), 'Môn thử');
    await t.tap(find.widgetWithText(AppButton, 'Hủy'));
    await t.pumpAndSettle();
    expect(repo.snapshot.courses.where((c) => c.code == 'TST101'), isEmpty);
    await t.tap(find.widgetWithText(AppButton, 'Thêm môn học'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'TST101');
    await t.enterText(find.byType(TextField).at(1), 'Môn thử');
    await t.pump();
    await t.tap(find.widgetWithText(AppButton, 'Thêm môn'));
    await t.pumpAndSettle();
    final created = repo.snapshot.courses.singleWhere(
      (c) => c.code == 'TST101',
    );
    expect(repo.snapshot.course(created.id)?.name, 'Môn thử');
    expect(created.id, isNot('tst101'));
    expect(find.byType(AcademicFormSheet), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Lớp: tìm kiếm lọc kết quả, tab sinh viên và modal nhóm', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(t, const ClassListScreen(), repo);
    await t.enterText(find.byType(TextField).first, 'KHÔNG TỒN TẠI');
    await t.pumpAndSettle();
    expect(find.text('Chưa có lớp nào'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await mount(t, const ClassDetailScreen(classId: 'se1701'), repo);
    await t.tap(find.text('Sinh viên').first);
    await t.pumpAndSettle();
    expect(find.text('Sinh viên'), findsWidgets);
    await t.tap(find.widgetWithText(AppButton, 'Thêm nhóm'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Nhóm kiểm thử');
    await t.pump();
    await t.tap(find.widgetWithText(AppButton, 'Tạo nhóm'));
    await t.pumpAndSettle();
    expect(
      repo.snapshot.classGroups('se1701').any((g) => g.name == 'Nhóm kiểm thử'),
      isTrue,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('Rule Set: thư viện, xem chi tiết, editor và gán phạm vi', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(t, const CourseDetailScreen(courseId: 'swp391'), repo);
    await t.tap(find.text('Checklist & tiêu chí'));
    await t.pumpAndSettle();
    expect(find.text('Checklist và tiêu chí đánh giá'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, 'Thư viện dùng chung'));
    await t.pumpAndSettle();
    expect(
      find.widgetWithText(AppButton, 'Đang áp dụng cho môn'),
      findsOneWidget,
    );
    await t.tap(find.widgetWithText(AppButton, 'Thêm bộ quy tắc'));
    await t.pumpAndSettle();
    expect(find.text('Thêm tiêu chí'), findsOneWidget);
    await t.ensureVisible(find.widgetWithText(AppButton, 'Thêm tiêu chí'));
    await t.tap(find.widgetWithText(AppButton, 'Thêm tiêu chí'));
    await t.pumpAndSettle();
    expect(find.textContaining('10 điểm'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('Đợt: chuyển Lab/Lớp, lưu cấu hình lặp lại được', (t) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(
      t,
      const OfferingDetailScreen(offeringId: 'off-f26-swp391'),
      repo,
    );
    await t.tap(find.widgetWithText(AppButton, 'Lưu cấu hình'));
    await t.pumpAndSettle();
    expect(find.text('Đã lưu'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, 'Đã lưu'));
    await t.pumpAndSettle();
    expect(repo.snapshot.revision, 2);
    await t.tap(find.text('Lab').first);
    await t.pumpAndSettle();
    expect(find.text('Cấu trúc Lab & Deliverables'), findsOneWidget);
    await t.tap(find.text('Lớp').first);
    await t.pumpAndSettle();
    expect(find.text('Các lớp thuộc đợt này'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Thêm sinh viên: QR, import mẫu và danh bạ', (t) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(t, const ClassDetailScreen(classId: 'se1701'), repo);
    await t.tap(find.widgetWithText(AppButton, 'Thêm sinh viên'));
    await t.pumpAndSettle();
    expect(find.byType(StudentEnrollmentSheet), findsOneWidget);
    await t.tap(find.text('Import danh sách'));
    await t.pumpAndSettle();
    await t.tap(find.text('Dùng tệp mẫu để xem trước'));
    await t.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    await t.tap(find.text('Nhập thủ công'));
    await t.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('Rule Set: nhân bản mở draft, hủy không ghi và lưu bản mới', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    final count = repo.snapshot.rules.length;
    await mount(t, const CourseDetailScreen(courseId: 'swp391'), repo);
    Future<void> clone() async {
      await t.ensureVisible(find.byType(AppMoreMenu).first);
      await t.tap(find.byType(AppMoreMenu).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Nhân bản'));
      await t.pumpAndSettle();
    }

    await clone();
    expect(repo.snapshot.rules.length, count);
    await t.tap(find.widgetWithText(AppButton, 'Hủy'));
    await t.pumpAndSettle();
    expect(repo.snapshot.rules.length, count);
    await clone();
    await t.tap(find.widgetWithText(AppButton, 'Lưu bộ quy tắc'));
    await t.pumpAndSettle();
    expect(repo.snapshot.rules.length, count + 1);
    expect(repo.snapshot.rules.last.active, isFalse);
    expect(repo.snapshot.rules.last.version, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('Rule Set: gán mặc định lớp qua ba bộ chọn phạm vi', (t) async {
    final repo = TestAcademicRepository(academicFixture());
    final rule = repo.snapshot.rules.firstWhere(
      (r) => repo.snapshot.courseRuleIds('swp391').contains(r.id),
    );
    await mount(t, const CourseDetailScreen(courseId: 'swp391'), repo);
    await t.ensureVisible(find.byType(AppMoreMenu).first);
    await t.tap(find.byType(AppMoreMenu).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Áp dụng'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await t.pumpAndSettle();
    await t.tap(find.text('SWP391 · Fall 2026').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('SE1701 — cấu hình riêng của lớp').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, 'Xác nhận áp dụng'));
    await t.pumpAndSettle();
    expect(repo.snapshot.classRoom('se1701')!.ruleOverride, rule.id);
    expect(find.byType(AcademicFormSheet), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Form lớp: số nhập dở không crash; hạ giới hạn giữ thành viên', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    final before = repo.snapshot
        .classGroups('se1701')
        .map((g) => g.toJson())
        .toList();
    await mount(t, const ClassListScreen(), repo);
    await t.ensureVisible(find.widgetWithText(AppButton, 'Chỉnh sửa').first);
    await t.tap(find.widgetWithText(AppButton, 'Chỉnh sửa').first);
    await t.pumpAndSettle();
    final limit = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is AcademicFieldView && w.field.key == 'maxGroupMembers',
      ),
      matching: find.byType(TextField),
    );
    await t.ensureVisible(limit);
    await t.enterText(limit, 'NaN');
    await t.pumpAndSettle();
    expect(
      t
          .widget<AppButton>(find.widgetWithText(AppButton, 'Lưu thay đổi'))
          .onPressed,
      isNull,
    );
    expect(t.takeException(), isNull);
    await t.enterText(limit, '1');
    await t.pumpAndSettle();
    expect(find.textContaining('Có nhóm vượt giới hạn mới'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, 'Lưu thay đổi'));
    await t.pumpAndSettle();
    expect(repo.snapshot.classRoom('se1701')!.memberLimit, 1);
    expect(
      repo.snapshot.classGroups('se1701').map((g) => g.toJson()).toList(),
      before,
    );
    expect(t.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('Chi tiết lớp: cả năm tab hoạt động ở $width dp', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(width, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await mount(
        t,
        const ClassDetailScreen(classId: 'se1701'),
        TestAcademicRepository(academicFixture()),
      );
      for (final label in [
        'Tổng quan',
        'Nhóm',
        'Sinh viên',
        'Dự án',
        'Yêu cầu đánh giá',
      ]) {
        final target = find.descendant(
          of: find.byType(AppTabs),
          matching: find.text(label),
        );
        await t.ensureVisible(target);
        await t.tap(target);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      expect(find.text('Yêu cầu đánh giá đang mở'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Xem tất cả'), findsOneWidget);
    });
  }
  testWidgets('Router sáu route thực và Back giữ Dashboard', (t) async {
    expect(
      AppBottomNavigation.activePath('/course-offerings/off-f26-swp391'),
      '',
    );
    expect(AppBottomNavigation.activePath('/classes/se1701'), '/projects');
    final repo = TestAcademicRepository(academicFixture());
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
          academicRepositoryProvider.overrideWithValue(repo),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await t.pumpAndSettle();
    final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
    for (final route in [
      '/courses',
      '/courses/swp391',
      '/course-offerings/off-f26-swp391',
      '/classes',
      '/classes/se1701',
      '/rule-sets',
    ]) {
      unawaited(nav.pushNamed(route));
      await t.pumpAndSettle();
      expect(find.text('Chức năng đang được chuẩn bị.'), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });
}

class _DeferredRepository implements AcademicRepository {
  Completer<AcademicSnapshot> completer = Completer();
  @override
  Future<AcademicSnapshot> load() => completer.future;
  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) async => next;
}
