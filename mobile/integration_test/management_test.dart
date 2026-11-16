import 'package:srs_review_ai_mobile/app/session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/repositories/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/repositories/academic/fake_academic_repository.dart';
import 'package:srs_review_ai_mobile/services/academic/fake_academic_service.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/document_reader_view_model.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/screens/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/widgets/app_disclosure.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const width = int.fromEnvironment('CAPTURE_WIDTH', defaultValue: 390);
  testWidgets(
    'Phase 3 Android: liên thông, quyền ghi, history, lỗi/retry và regression',
    (t) async {
      WidgetController.hitTestWarningShouldBeFatal = true;
      final repo = _NativeRepository();
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
      final root = t.element(find.text('Xin chào, Nguyễn Văn An'));
      final container = ProviderScope.containerOf(root);
      final nav = Navigator.of(root);
      final media = MediaQuery.of(root);
      expect(media.size.width, closeTo(width, 1));
      binding.reportData = {
        'captureWidth': width,
        'metrics': {
          'width': media.size.width,
          'height': media.size.height,
          'pixelRatio': t.view.devicePixelRatio,
          'topInset': t.view.padding.top / t.view.devicePixelRatio,
          'bottomInset': t.view.padding.bottom / t.view.devicePixelRatio,
          'screens': <String, dynamic>{},
          'checks': <String>[],
        },
      };
      await binding.convertFlutterSurfaceToImage();
      await t.pumpAndSettle();
      Future<void> capture(String name) async {
        await t.pump(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(t.takeException(), isNull);
        final headings = find.byType(AppPageHeading);
        if (headings.evaluate().isNotEmpty) {
          final rect = t.getRect(headings.first);
          ((binding.reportData!['metrics'] as Map)['screens'] as Map)[name] = {
            'heading': {
              'x': rect.left,
              'y': rect.top,
              'width': rect.width,
              'height': rect.height,
            },
          };
        }
        await binding.takeScreenshot('flutter-$width-$name');
      }

      Future<void> open(String path) async {
        unawaited(nav.pushNamed(path));
        await t.pumpAndSettle();
      }

      Future<void> back() async {
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
      }

      Future<void> tap(Finder f) async {
        await Scrollable.ensureVisible(
          t.element(f),
          alignmentPolicy:
              t.getRect(f).top <
                  t.view.padding.top / t.view.devicePixelRatio + 57
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        await t.tap(f);
        await t.pumpAndSettle();
      }

      Future<void> tab(String label) async => tap(
        find
            .descendant(of: find.byType(AppTabs), matching: find.text(label))
            .first,
      );
      Finder button(String label) => find.widgetWithText(AppButton, label);
      Finder field(String key) => find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is AcademicFieldView && w.field.key == key,
            ),
            matching: find.byType(TextField),
          )
          .first;
      Future<void> input(String key, String value) async {
        await t.ensureVisible(field(key));
        await t.enterText(field(key), value);
        await t.pump();
      }

      Future<void> keyboardClose() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
      }

      void check(String label) =>
          ((binding.reportData!['metrics'] as Map)['checks'] as List).add(
            label,
          );
      await capture('dashboard');
      final routes = {
        'groups': '/groups',
        'group': '/groups/se1701-group-01',
        'projects': '/projects',
        'project': '/projects/smart-campus-management',
        'project-documents': '/projects/smart-campus-management/documents',
        'registrations': '/project-registrations',
        'documents': '/documents',
        'reviews': '/reviews',
        'workspace': '/reviews/review-001',
        'ai-result': '/reviews/review-001/ai-result',
        'ai-completed': '/reviews/demo-ready-persona/ai-result',
        'workspace-ai-completed': '/reviews/demo-ready-persona',
        'versions': '/reviews/review-001/versions',
        'review-history': '/reviews/review-001/history',
        'history': '/review-history',
        'courses': '/courses',
        'offering': '/course-offerings/off-f26-swp391',
        'class': '/classes/se1701',
        'rules': '/rule-sets',
      };
      for (final e in routes.entries) {
        await open(e.value);
        await capture(e.key);
        if (e.key == 'group') {
          await tap(button('Thêm thành viên'));
          await capture('group-member');
          await tap(button('Hủy'));
          await tap(find.byTooltip('Thao tác khác'));
          await t.pumpAndSettle();
          await t.tap(find.text('Đổi tên nhóm').last);
          await t.pumpAndSettle();
          await capture('group-rename');
          await tap(button('Hủy'));
        }
        if (e.key == 'projects') {
          await tap(button('Tạo dự án'));
          await capture('project-form');
          await tap(button('Hủy'));
        }
        if (e.key == 'project') {
          for (final label in [
            'Tài liệu',
            'Thành viên',
            'Lịch sử đánh giá',
            'Thông tin',
          ]) {
            await tab(label);
            await capture(
              'project-${['Tài liệu', 'Thành viên', 'Lịch sử đánh giá', 'Thông tin'].indexOf(label) + 1}',
            );
          }
        }
        if (e.key == 'workspace') {
          await tap(find.byTooltip('Trang sau'));
          expect(find.text('Trang 2 / 12'), findsOneWidget);
          await tap(find.byTooltip('Phóng to tài liệu'));
          await t.drag(
            find.byType(SingleChildScrollView).last,
            const Offset(0, -300),
          );
          await t.pumpAndSettle();
          const readingKey = 'reader:review-001:v2';
          final offset = container
              .read(documentReaderProvider(readingKey))
              .offset;
          expect(offset, isNotNull);
          expect(offset! > 0, isTrue);
          await back();
          await tap(find.byTooltip('Phóng to tài liệu'));
          expect(
            container.read(documentReaderProvider(readingKey)).offset,
            closeTo(offset, 1),
          );
          await back();
          await tap(find.byTooltip('Trang trước'));
          check(
            'Đọc tài liệu: chuyển trang, toàn màn hình, Back và khôi phục vị trí cuộn',
          );
          for (final label in ['AI', 'Phản hồi', 'Lịch sử']) {
            await tab(label);
            await capture(
              'workspace-${['AI', 'Phản hồi', 'Lịch sử'].indexOf(label) + 1}',
            );
          }
          await tap(find.text('Thông tin').first);
          await t.pumpAndSettle();
          await capture('review-context');
          await t.tap(find.byTooltip('Đóng'));
          await t.pumpAndSettle();
        }
        if (e.key == 'workspace-ai-completed') {
          await tab('AI');
          final s = container.read(academicViewModelProvider).requireValue;
          final run = s.evaluation(s.review('demo-ready-persona')!)!;
          final id = run
              .values('criterionResults')
              .firstWhere(
                (c) =>
                    c['score'] == null ||
                    (c['score'] as num) < (c['maxScore'] as num),
              )['criterionId']
              .toString();
          final f = find.byWidgetPredicate(
            (w) => w is AppDisclosure && w.title.startsWith('$id ·'),
          );
          await tap(f);
          await Scrollable.ensureVisible(t.element(f), alignment: 0);
          await t.pumpAndSettle();
          await capture('criteria');
        }
        await back();
      }
      check(
        '13 route Phase 3 và regression Dashboard/Course/Offering/Class/Rule Set hiển thị native',
      );
      // Mọi ảnh baseline ở trên được chụp trước mutation để so sánh với React cùng fixture.
      await open('/groups/se1701-group-01');
      final before = container.read(academicViewModelProvider).requireValue;
      final original = before.group('se1701-group-01')!;
      final studentId = original.memberIds.first;
      await tap(find.widgetWithText(TextButton, 'Xóa khỏi nhóm').first);
      await t.tap(button('Xác nhận'));
      await t.pumpAndSettle();
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .group(original.id)!
            .memberIds
            .contains(studentId),
        isFalse,
      );
      await back();
      await open('/groups');
      await tap(button('Thêm nhóm').first);
      await input('name', 'Nhóm Android Phase 3');
      await keyboardClose();
      await tap(button('Tạo nhóm'));
      final created = container
          .read(academicViewModelProvider)
          .requireValue
          .groups
          .last;
      await back();
      await open('/groups/${created.id}');
      await tap(button('Thêm thành viên'));
      await tap(button('Thêm vào nhóm'));
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .group(created.id)!
            .memberIds,
        [studentId],
      );
      await tap(button('Tạo dự án'));
      await input('name', 'Dự án Android Phase 3');
      await keyboardClose();
      await tap(button('Tạo dự án').last);
      expect(find.byType(ManagementFormSheet), findsNothing);
      final projectId = container
          .read(academicViewModelProvider)
          .requireValue
          .group(created.id)!
          .projectId;
      expect(projectId, isNotEmpty);
      await tap(button('Xem dự án'));
      expect(find.text('Dự án Android Phase 3'), findsOneWidget);
      await tab('Thành viên');
      expect(
        find.text(before.students.firstWhere((st) => st.id == studentId).name),
        findsOneWidget,
      );
      check(
        'Bỏ thành viên → tạo nhóm → thêm đúng sinh viên → tạo dự án → thành viên dự án đồng bộ',
      );
      await tap(find.byTooltip('Thao tác khác'));
      await t.pumpAndSettle();
      await t.tap(find.text('Lưu trữ dự án').last);
      await t.pumpAndSettle();
      await t.tap(button('Xác nhận'));
      await t.pumpAndSettle();
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .project(projectId)!
            .text('state'),
        'archived',
      );
      await tap(find.byTooltip('Thao tác khác'));
      await t.pumpAndSettle();
      await t.tap(find.text('Khôi phục dự án').last);
      await t.pumpAndSettle();
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .project(projectId)!
            .text('state'),
        'active',
      );
      check('Lưu trữ/khôi phục dự án giữ dữ liệu');
      nav.popUntil((r) => r.isFirst);
      await t.pumpAndSettle();
      await open('/reviews/review-001');
      await tab('Phản hồi');
      await input('message', 'Phản hồi Android cần làm rõ ngoại lệ');
      await keyboardClose();
      await tap(button('Thêm phản hồi'));
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .review('review-001')!
            .text('supervisorStatus'),
        'inReview',
      );
      await t.tap(button('Phê duyệt'));
      await t.pumpAndSettle();
      await capture('decision');
      await tap(button('Hủy'));
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .review('review-001')!
            .text('supervisorStatus'),
        'inReview',
      );
      await t.tap(button('Phê duyệt'));
      await t.pumpAndSettle();
      await tap(button('Xác nhận quyết định'));
      final after = container.read(academicViewModelProvider).requireValue;
      expect(after.review('review-001')!.text('supervisorStatus'), 'approved');
      expect(after.feedbackFor('review-001').last.flag('official'), isTrue);
      expect(after.eventsFor('review-001').last.text('quote'), isEmpty);
      expect(
        after.eventsFor('review-001').last.strings('selectedFeedbackIds'),
        contains(after.feedbackFor('review-001').last.id),
      );
      expect(
        (after.dashboardJson['requests'] as List).firstWhere(
          (r) => r['id'] == 'review-001',
        )['supervisorStatus'],
        'approved',
      );
      check(
        'Phản hồi nháp → hủy quyết định → phê duyệt → history và Dashboard liên thông',
      );
      await back();
      await open('/courses/swp391');
      await tap(
        find.byWidgetPredicate(
          (w) => w is AppDisclosure && w.title.startsWith('Đợt học, lớp'),
        ),
      );
      await tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is AppButton &&
                  w.label.contains('Fall 2026') &&
                  w.label.contains('Cấu hình'),
            )
            .first,
      );
      await tab('Lớp');
      await tap(button('Chi tiết lớp').first);
      await tap(button('Quản lý nhóm').first);
      await tap(button('Xem dự án'));
      await tap(button('Mở tài liệu'));
      expect(find.text('Tài liệu dự án'), findsOneWidget);
      await tap(button('Đánh giá').first);
      await tap(find.text('Thông tin').first);
      expect(find.text('Bộ quy tắc'), findsOneWidget);
      final names = container
          .read(academicViewModelProvider)
          .requireValue
          .rules
          .map((r) => r.name);
      expect(
        names.any((name) => find.text(name).evaluate().isNotEmpty),
        isTrue,
      );
      nav.popUntil((r) => r.settings.name == '/courses/swp391' || r.isFirst);
      await t.pumpAndSettle();
      await tap(button('Cấu hình nộp bài').first);
      expect(find.byType(AcademicFormSheet), findsOneWidget);
      await t.tap(find.byTooltip('Đóng'));
      await t.pumpAndSettle();
      check(
        'Bấm Course → Offering → Class → Group → Project → Documents → Review; đối chiếu Rule Set và Back về Course để mở editor',
      );
      nav.popUntil((r) => r.isFirst);
      await t.pumpAndSettle();
      await open('/reviews/demo-ready-persona');
      await tab('AI');
      final aiBefore = container.read(academicViewModelProvider).requireValue;
      final run = aiBefore.evaluation(aiBefore.review('demo-ready-persona')!)!;
      final criterion = run
          .values('criterionResults')
          .firstWhere(
            (c) =>
                c['score'] == null ||
                (c['score'] as num) < (c['maxScore'] as num),
          )['criterionId']
          .toString();
      await tap(
        find.byWidgetPredicate(
          (w) => w is AppDisclosure && w.title.startsWith('$criterion ·'),
        ),
      );
      await tap(button('Thêm vào phản hồi nháp').first);
      expect(
        container
            .read(academicViewModelProvider)
            .requireValue
            .feedbackFor('demo-ready-persona')
            .length,
        aiBefore.feedbackFor('demo-ready-persona').length + 1,
      );
      await container
          .read(academicViewModelProvider.notifier)
          .runEvaluation('demo-ready-persona', simulateError: true);
      await t.pumpAndSettle();
      await capture('ai-error');
      await tap(button('Thử lại Đánh giá AI'));
      final aiAfter = container.read(academicViewModelProvider).requireValue;
      expect(
        aiAfter
            .evaluation(aiAfter.review('demo-ready-persona')!)!
            .text('evaluationStatus'),
        'completed',
      );
      expect(
        aiAfter.review('demo-ready-persona')!.text('supervisorStatus'),
        'inReview',
      );
      check(
        'AI theo tiêu chí: thêm finding vào nháp → lỗi mô phỏng → retry → kết quả mới, không tự phê duyệt',
      );
      await back();
      await open('/groups');
      repo.failLoad = true;
      container.read(academicViewModelProvider.notifier).retry();
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      await capture('error');
      repo.failLoad = false;
      await t.tap(button('Thử lại'));
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsNothing);
      check('Lỗi tải/retry native phục hồi đúng dữ liệu sau mutation');
      await back();
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}

/// Chỉ tiêm lỗi mạng giả vào test; kho thật trong phiên vẫn dùng service/revision của ứng dụng.
class _NativeRepository implements AcademicRepository {
  final inner = FakeAcademicRepository(FakeAcademicService(rootBundle));
  bool failLoad = false;
  @override
  Future<AcademicSnapshot> load() {
    if (failLoad) throw const AcademicFailure('Lỗi kiểm thử');
    return inner.load();
  }

  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) => inner.commit(next, expectedRevision: expectedRevision);
}
