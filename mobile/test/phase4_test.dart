import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/app/session.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/repositories/notification_repository.dart';
import 'package:srs_review_ai_mobile/screens/account/account_screens.dart';
import 'package:srs_review_ai_mobile/screens/account/login_screen.dart';
import 'package:srs_review_ai_mobile/screens/academic/directory_screens.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/student_enrollment_sheet.dart';
import 'package:srs_review_ai_mobile/screens/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/directory_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/dashboard/dashboard_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';

import 'support/academic_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<AcademicRecord> notificationFixture;
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await font.load();
    notificationFixture = await FakeNotificationRepository(rootBundle).load();
  });
  group('Phase 4 data integration', () {
    late TestAcademicRepository repo;
    late ProviderContainer c;
    late AcademicViewModel vm;
    setUp(() async {
      repo = TestAcademicRepository(academicFixture());
      c = ProviderContainer(
        overrides: [academicRepositoryProvider.overrideWithValue(repo)],
      );
      await c.read(academicViewModelProvider.future);
      vm = c.read(academicViewModelProvider.notifier);
    });
    tearDown(() => c.dispose());
    AcademicJson draft() => {
      'name': 'Spring 2027',
      'academicYear': '2026–2027',
      'startDate': '2027-01-01',
      'endDate': '2027-05-01',
      'description': 'New semester',
    };
    test(
      'Semester create/edit/archive/restore/delete keeps other modules intact',
      () async {
        final before = repo.snapshot.toJson();
        await vm.saveSemester(draft());
        final sem = repo.snapshot.semesters.last;
        await vm.saveSemester({...sem.toJson(), 'name': 'Spring updated'});
        await vm.archiveSemester(sem.id, true);
        expect(repo.snapshot.semester(sem.id)!.archived, true);
        await vm.archiveSemester(sem.id, false);
        expect(repo.snapshot.semester(sem.id)!.name, 'Spring updated');
        await vm.deleteSemester(sem.id);
        for (final key in [
          'classes',
          'groups',
          'projects',
          'reviewState',
          'offerings',
        ]) {
          expect(repo.snapshot.toJson()[key], before[key]);
        }
      },
    );
    test('Semester dates and references reject atomically; failed writes preserve snapshot', () async {
      final before = repo.snapshot.toJson();
      await expectLater(
        vm.saveSemester({...draft(), 'endDate': '2026-01-01'}),
        throwsA(isA<AcademicFailure>()),
      );
      await expectLater(
        vm.deleteSemester(repo.snapshot.classes.first.semesterId),
        throwsA(isA<AcademicFailure>()),
      );
      expect(repo.snapshot.toJson(), before);
      repo.failWrite = true;
      await expectLater(
        vm.saveSemester(draft()),
        throwsA(isA<AcademicFailure>()),
      );
      expect(repo.snapshot.toJson(), before);
    });
    test(
      'Offering without classes still prevents orphaning on semester delete',
      () async {
        await vm.saveSemester(draft());
        final sem = repo.snapshot.semesters.last;
        await vm.mutate(
          (s) => s.replaceCollection('offerings', [
            ...s.offerings.map((o) => o.toJson()),
            {
              ...s.offerings.first.toJson(),
              'id': 'empty-linked-offering',
              'semesterId': sem.id,
            },
          ]),
        );
        await expectLater(
          vm.deleteSemester(sem.id),
          throwsA(isA<AcademicFailure>()),
        );
        expect(repo.snapshot.semester(sem.id), isNotNull);
      },
    );
    test(
      'Directory cascade resets lower filters; query searches code/name/email',
      () {
        final keep = c.listen(studentDirectoryProvider, (_, _) {});
        final filters = c.read(studentDirectoryProvider.notifier);
        final cls = repo.snapshot.classes.first;
        filters.set('class', cls.id);
        expect(filters.visible.every((s) => s.text('classId') == cls.id), true);
        filters.set('course', cls.courseId);
        expect(c.read(studentDirectoryProvider).text('class'), '');
        filters.set('semester', cls.semesterId);
        expect(c.read(studentDirectoryProvider).text('course'), '');
        filters.clear();
        final student = filters.visible.first;
        for (final q in [
          student.studentCode,
          student.name,
          student.text('email'),
        ]) {
          filters.set('query', q);
          expect(filters.visible.map((s) => s.id), contains(student.id));
        }
        filters.set('query', 'no-such-student-999');
        expect(filters.visible, isEmpty);
        keep.close();
      },
    );
    test('Enrollment/group/project mutations update directory and Dashboard from same repository', () async {
      final keep = c.listen(studentDirectoryProvider, (_, _) {});
      await vm.enrollStudents('se1701', [
        {
          'studentCode': 'SE989891',
          'name': 'Phase Four',
          'email': 'phase4@test.local',
        },
      ]);
      final st = repo.snapshot.students.last;
      expect(
        c.read(studentDirectoryProvider.notifier).visible.map((s) => s.id),
        contains(st.id),
      );
      await vm.createGroup('se1701', 'Phase 4 integration');
      final g = repo.snapshot.groups.last;
      await vm.addGroupMember(g.id, st.id);
      await vm.saveProject({
        'groupId': g.id,
        'name': 'Phase 4 project',
        'startDate': '2026-09-01',
        'deadline': '2026-12-15T23:59',
      });
      final p = repo.snapshot.project(repo.snapshot.group(g.id)!.projectId)!;
      expect(p.text('groupId'), g.id);
      expect(p.values('members').single['name'], st.name);
      final dashboard = await c.read(dashboardViewModelProvider.future);
      expect(dashboard.snapshot.projects.map((p) => p.id), contains(p.id));
      await vm.setClassState('se1701', 'archived');
      await expectLater(
        vm.renameGroup(g.id, 'blocked'),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.setClassState('se1701', 'active');
      await vm.renameGroup(g.id, 'Restored');
      expect(repo.snapshot.group(g.id)!.name, 'Restored');
      keep.close();
    });
    for (final decision in [0, 1, 2]) {
      test('Decision $decision never copies student submission note', () async {
        final r = repo.snapshot
            .reviewRows('requests')
            .firstWhere(
              (r) =>
                  !repo.snapshot.completed(r) &&
                  repo.snapshot.supervisorBlock(r) == null,
            );
        final spec = AcademicFormSpec(
          'decision',
          data: {...r.toJson(), 'note': 'STUDENT PRIVATE SUBMISSION NOTE'},
          section: decision,
        );
        final keep = c.listen(managementFormProvider(spec), (_, _) {});
        final form = c.read(managementFormProvider(spec).notifier);
        expect(form.draft.text('note'), '');
        expect(form.draft.text('reason'), '');
        if (decision == 1) form.set('note', 'SUPERVISOR REVISION NOTE');
        if (decision == 2) form.set('reason', 'Khác');
        if (decision == 2) form.set('note', 'SUPERVISOR REJECTION NOTE');
        expect(await form.save(), true);
        final event = repo.snapshot.eventsFor(r.id).last;
        expect(event.text('quote'), isNot(contains('STUDENT PRIVATE')));
        if (decision == 0) expect(event.text('quote'), '');
        keep.close();
      });
    }
    test(
      'Mock session rejects Student and unknown roles and signs Supervisor out',
      () {
        final auth = c.read(sessionProvider.notifier);
        expect(
          () => auth.signIn('admin', 'a@b.local', 'p'),
          throwsFormatException,
        );
        expect(
          () => auth.signIn('student', 'a@b.local', 'p'),
          throwsFormatException,
        );
        expect(c.read(sessionProvider), isNull);
        auth.signIn('supervisor', 'a@b.local', 'p');
        expect(c.read(sessionProvider)!.isSupervisor, true);
        expect(
          () => auth.signIn('student', 'a@b.local', 'p'),
          throwsFormatException,
        );
        expect(c.read(sessionProvider)!.isSupervisor, true);
        auth.signOut();
        expect(c.read(sessionProvider), isNull);
      },
    );
    test('Supervisor notification category filters match React and exact destinations', () async {
      final all = await FakeNotificationRepository(rootBundle).load();
      expect(all.where((n) => notificationMatches(n, 1)).length, 2);
      expect(all.where((n) => notificationMatches(n, 3)).single.id, 'n4');
      expect(
        all.where((n) => notificationMatches(n, 4)).single.text('link'),
        '/reviews/review-008',
      );
      for (final n in all) {
        expect(repo.snapshot.review(n.text('link').split('/').last), isNotNull);
      }
    });
  });

  Future<ProviderContainer> launch(
    WidgetTester t, {
    AppSession? session,
  }) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          academicRepositoryProvider.overrideWithValue(
            TestAcademicRepository(academicFixture()),
          ),
          initialSessionProvider.overrideWithValue(session),
          notificationsProvider.overrideWith(
            (ref) async => notificationFixture,
          ),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await t.pumpAndSettle();
    return ProviderScope.containerOf(t.element(find.byType(SrsReviewApp)));
  }

  Future<void> tapVisible(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'Login validation, protected routes, logout and Android Back cannot revive session',
    (t) async {
      final c = await launch(t);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Đăng nhập giảng viên'), findsOneWidget);
      expect(find.text('Sinh viên'), findsNothing);
      expect(find.text('Bạn đăng nhập với vai trò'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await t.enterText(find.byType(TextFormField).first, 'invalid');
      await t.tap(find.text('Đăng nhập').last);
      await t.pumpAndSettle();
      expect(find.text('Nhập email hợp lệ.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).last, '');
      await t.tap(find.text('Đăng nhập').last);
      await t.pumpAndSettle();
      expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
      expect(c.read(sessionProvider), isNull);
      await t.enterText(find.byType(TextFormField).last, 'password');
      await t.enterText(
        find.byType(TextFormField).first,
        'an.nguyen@university.edu.vn',
      );
      await t.tap(find.text('Đăng nhập').last);
      await t.pumpAndSettle();
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
      unawaited(nav.pushNamed('/profile'));
      await t.pumpAndSettle();
      await tapVisible(t, find.text('Đăng xuất'));
      expect(c.read(sessionProvider), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsNothing);
    },
  );
  for (final role in ['student', 'admin', '']) {
    testWidgets('Restored $role session cannot access Supervisor routes', (
      t,
    ) async {
      final c = await launch(t, session: AppSession(role));
      expect(c.read(sessionProvider), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigation), findsNothing);
      final nav = Navigator.of(t.element(find.byType(LoginScreen)));
      for (final path in [
        '/dashboard',
        '/profile',
        '/reviews/review-001',
        '/student/dashboard',
      ]) {
        unawaited(nav.pushNamed(path));
        await t.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(AppBottomNavigation), findsNothing);
        expect(find.byType(ProfileScreen), findsNothing);
        expect(find.text('Xin chào, Nguyễn Văn An'), findsNothing);
        expect(c.read(sessionProvider), isNull);
        nav.pop();
        await t.pumpAndSettle();
      }
    });
  }

  testWidgets('Legacy Student route is not a Supervisor Dashboard alias', (
    t,
  ) async {
    await launch(t, session: const AppSession('supervisor'));
    final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
    unawaited(nav.pushNamed('/student/dashboard'));
    await t.pumpAndSettle();
    expect(find.text('Không tìm thấy trang'), findsOneWidget);
    expect(find.text('Xin chào, Nguyễn Văn An'), findsNothing);
  });

  testWidgets(
    'Route guard denies an invalid session even if supplied by an adapter',
    (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_UntrustedStudentSession.new),
          ],
          child: const SrsReviewApp(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigation), findsNothing);
      final nav = Navigator.of(t.element(find.byType(LoginScreen)));
      unawaited(nav.pushNamed('/reviews/review-001'));
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigation), findsNothing);
      expect(find.text('Xin chào, Nguyễn Văn An'), findsNothing);
    },
  );
  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets(
      'New pages, semester form and enrollment at ${width.toInt()}dp with Inter',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await launch(t, session: const AppSession('supervisor'));
        final nav = Navigator.of(
          t.element(find.text('Xin chào, Nguyễn Văn An')),
        );
        for (final (path, type) in [
          ('/profile', ProfileScreen),
          ('/notifications', NotificationsScreen),
          ('/semesters', SemesterListScreen),
          ('/students', StudentDirectoryScreen),
        ]) {
          unawaited(nav.pushNamed(path));
          await t.pumpAndSettle();
          expect(find.byType(type), findsOneWidget);
          expect(t.takeException(), isNull, reason: path);
          if (path == '/semesters') {
            await tapVisible(t, find.text('Tạo học kỳ'));
            expect(find.byType(ManagementFormSheet), findsOneWidget);
            t.view.viewInsets = FakeViewPadding(bottom: 280);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            t.view.resetViewInsets();
            await t.pumpAndSettle();
            await tapVisible(t, find.text('Hủy'));
          }
          if (path == '/students') {
            await t.enterText(find.byType(TextField).first, 'no-student-match');
            await t.pumpAndSettle();
            expect(find.text('Không tìm thấy sinh viên'), findsOneWidget);
            await tapVisible(t, find.text('Thêm sinh viên'));
            await tapVisible(t, find.text('Tiếp tục'));
            expect(find.byType(StudentEnrollmentSheet), findsOneWidget);
            expect(t.takeException(), isNull);
            nav.pop();
            await t.pumpAndSettle();
          }
          nav.pop();
          await t.pumpAndSettle();
        }
        unawaited(nav.pushNamed('/dashboard'));
        await t.pumpAndSettle();
        expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
        nav.pop();
        await t.pumpAndSettle();
        unawaited(nav.pushNamed('/does-not-exist'));
        await t.pumpAndSettle();
        expect(find.text('Không tìm thấy trang'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}

// Simulates untrusted auth-adapter output to verify the independent UI guard.
class _UntrustedStudentSession extends SessionViewModel {
  @override
  AppSession? build() => const AppSession('student');
}
