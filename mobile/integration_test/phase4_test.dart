import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/session.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/screens/account/login_screen.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/student_enrollment_sheet.dart';
import 'package:srs_review_ai_mobile/screens/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/directory_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_form_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const width = int.fromEnvironment('CAPTURE_WIDTH', defaultValue: 390);
  testWidgets(
    'Phase 4 changed routes, mutations, role gate and keyboard at ${width}dp',
    (t) async {
      WidgetController.hitTestWarningShouldBeFatal = true;
      await t.pumpWidget(const ProviderScope(child: SrsReviewApp()));
      await t.pumpAndSettle();
      final c = ProviderScope.containerOf(t.element(find.byType(SrsReviewApp)));
      expect(find.byType(LoginScreen), findsOneWidget);
      final media = MediaQuery.of(t.element(find.byType(LoginScreen)));
      expect(media.size.width, closeTo(width, 1));
      binding.reportData = {'captureWidth': width, 'checks': <String>[]};
      await binding.convertFlutterSurfaceToImage();
      await t.pumpAndSettle();
      Future<void> capture(String name) async {
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await binding.takeScreenshot('flutter-$width-$name');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await capture('login');
      await tap(find.text('Đăng nhập').last);
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
      Future<void> open(String path) async {
        unawaited(nav.pushNamed(path));
        await t.pumpAndSettle();
      }

      Future<void> back() async {
        nav.pop();
        await t.pumpAndSettle();
      }

      await open('/profile');
      await capture('profile');
      await back();
      await open('/notifications');
      await capture('notifications');
      await tap(find.text('Hạn nộp'));
      expect(find.textContaining('chờ đánh giá 4 ngày'), findsOneWidget);
      await tap(find.text('Xem chi tiết →'));
      expect(find.text('Sequence Diagram'), findsWidgets);
      await back();
      await back();
      await open('/semesters');
      await capture('semesters');
      await tap(find.text('Tạo học kỳ'));
      await capture('semester-form');
      final sheet = t.element(find.byType(ManagementFormSheet));
      final spec = t
          .widget<ManagementFormSheet>(find.byType(ManagementFormSheet))
          .spec;
      final form = c.read(managementFormProvider(spec).notifier);
      final first = find
          .descendant(
            of: find.byType(ManagementFormSheet),
            matching: find.byType(TextField),
          )
          .first;
      await tap(first);
      await t.enterText(first, 'Phase 4 Native');
      await t.pumpAndSettle();
      binding.reportData!['nativeKeyboardInset'] = MediaQuery.viewInsetsOf(
        sheet,
      ).bottom;
      await capture('semester-keyboard');
      expect(t.takeException(), isNull);
      form.set('academicYear', '2026–2027');
      form.set('startDate', '2027-01-01');
      form.set('endDate', '2027-05-01');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await tap(
        find.descendant(
          of: find.byType(ManagementFormSheet),
          matching: find.widgetWithText(AppButton, 'Lưu'),
        ),
      );
      expect(
        c.read(academicViewModelProvider).requireValue.semesters.last.name,
        'Phase 4 Native',
      );
      final vm = c.read(academicViewModelProvider.notifier);
      final sem = vm.snapshot.semesters.last;
      await vm.archiveSemester(sem.id, true);
      expect(vm.snapshot.semester(sem.id)!.archived, true);
      await vm.archiveSemester(sem.id, false);
      await vm.deleteSemester(sem.id);
      await back();
      await open('/students');
      await capture('students');
      await tap(find.text('Thêm sinh viên'));
      await tap(find.text('Tiếp tục'));
      expect(find.byType(StudentEnrollmentSheet), findsOneWidget);
      await capture('enrollment');
      await back();
      await back();
      await vm.enrollStudents('se1701', [
        {
          'studentCode': 'SE989891',
          'name': 'Native Phase Four',
          'email': 'phase4@test.local',
        },
      ]);
      final st = vm.snapshot.students.last;
      await vm.createGroup('se1701', 'Native Phase 4');
      final g = vm.snapshot.groups.last;
      await vm.addGroupMember(g.id, st.id);
      await vm.saveProject({
        'groupId': g.id,
        'name': 'Native integration',
        'startDate': '2026-09-01',
        'deadline': '2026-12-15T23:59',
      });
      final p = vm.snapshot.project(vm.snapshot.group(g.id)!.projectId)!;
      expect(p.values('members').single['name'], st.name);
      for (final path in [
        '/classes/se1701',
        '/groups/${g.id}',
        '/projects/${p.id}',
        '/reviews/review-001',
      ]) {
        await open(path);
        expect(t.takeException(), isNull);
        await back();
      }
      final r = vm.snapshot
          .reviewRows('requests')
          .firstWhere(
            (r) =>
                !vm.snapshot.completed(r) &&
                vm.snapshot.supervisorBlock(r) == null,
          );
      await open('/reviews/${r.id}');
      final decision = AcademicFormSpec(
        'decision',
        data: {...r.toJson(), 'note': 'STUDENT NOTE MUST NOT COPY'},
      );
      unawaited(
        showManagementForm(
          t.element(find.byType(AppBottomNavigation)),
          decision,
        ),
      );
      await t.pumpAndSettle();
      expect(c.read(managementFormProvider(decision)).draft.text('note'), '');
      await capture('decision-note-regression');
      await tap(find.text('Hủy'));
      await back();
      await open('/dashboard');
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      await back();
      await open('/unknown-phase4');
      expect(find.text('Không tìm thấy trang'), findsOneWidget);
      await back();
      await open('/profile');
      await tap(find.text('Đăng xuất'));
      expect(find.byType(LoginScreen), findsOneWidget);
      // Android Back at the signed-out root exits the Activity. Back isolation
      // is covered in widget tests; keep this Activity alive to submit evidence.
      expect(find.byType(AppBottomNavigation), findsNothing);
      expect(find.text('Đăng nhập giảng viên'), findsOneWidget);
      expect(find.text('Sinh viên'), findsNothing);
      expect(
        () => c
            .read(sessionProvider.notifier)
            .signIn('student', 'a@b.local', 'p'),
        throwsFormatException,
      );
      expect(c.read(sessionProvider), isNull);
      expect(find.byType(AppBottomNavigation), findsNothing);
      (binding.reportData!['checks'] as List<String>).addAll(<String>[
        'new routes and exact notification link',
        'semester native form and mutations',
        'enrollment sheet',
        'academic/group/project/review navigation',
        'student note separation',
        'Supervisor-only login, rejected Student session and logout (Back isolation covered by widget tests)',
      ]);
    },
  );
}
