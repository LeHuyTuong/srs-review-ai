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
import 'package:srs_review_ai_mobile/models/session_scope.dart';
import 'package:srs_review_ai_mobile/repositories/academic/fake_academic_repository.dart';
import 'package:srs_review_ai_mobile/screens/account/login_screen.dart';
import 'package:srs_review_ai_mobile/services/academic/fake_academic_service.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/class_filter_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/directory_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_list_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/dashboard/dashboard_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';

import 'support/academic_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
  });
  group('Group A runtime regressions', () {
    late TestAcademicRepository repository;
    late ProviderContainer container;
    late AcademicViewModel vm;
    setUp(() async {
      repository = TestAcademicRepository(academicFixture());
      container = ProviderContainer(
        overrides: [
          academicRepositoryProvider.overrideWithValue(repository),
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
        ],
      );
      await container.read(academicViewModelProvider.future);
      vm = container.read(academicViewModelProvider.notifier);
    });
    tearDown(() => container.dispose());

    test(
      'B03 distinct codes with identical old slug retain both identities',
      () async {
        final before = repository.snapshot;
        await vm.saveCourse({'code': 'AUDIT A', 'name': 'First'});
        await vm.saveCourse({'code': 'AUDIT-A', 'name': 'Second'});
        final after = repository.snapshot;
        expect(after.courses.length, before.courses.length + 2);
        final first = after.courses.firstWhere((c) => c.code == 'AUDIT A');
        final second = after.courses.firstWhere((c) => c.code == 'AUDIT-A');
        expect(first.id, isNot(second.id));
        for (final key in ['offerings', 'classes', 'ruleSets']) {
          expect(after.data[key], before.data[key]);
        }
        await vm.saveCourse({...first.toJson(), 'code': 'RENAMED'});
        expect(repository.snapshot.course(first.id)!.code, 'RENAMED');
      },
    );

    test('B03 duplicate create/edit and unknown ID fail atomically', () async {
      final before = repository.snapshot.toJson();
      final first = repository.snapshot.courses.first;
      final second = repository.snapshot.courses[1];
      for (final draft in [
        {'code': ' ${first.code.toLowerCase()} ', 'name': 'Duplicate'},
        {...second.toJson(), 'code': first.code},
        {'id': 'nonexistent', 'code': 'NEW', 'name': 'Unknown edit'},
      ]) {
        await expectLater(
          vm.saveCourse(draft),
          throwsA(isA<AcademicFailure>()),
        );
        expect(repository.snapshot.toJson(), before);
      }
    });

    test(
      'B02 detached valid project remains in list and Dashboard totals',
      () async {
        final history = repository.snapshot.data['reviewState'];
        await vm.createGroup('se1701', 'Empty detachable group');
        final group = repository.snapshot.groups.last;
        await vm.saveProject({
          'groupId': group.id,
          'name': 'Detached regression',
          'startDate': '2026-09-01',
          'deadline': '2026-12-15T23:59',
        });
        final id = repository.snapshot.group(group.id)!.projectId;
        final linked = await container.read(dashboardViewModelProvider.future);
        await vm.deleteGroup(group.id);
        final snapshot = repository.snapshot;
        expect(snapshot.group(group.id), isNull);
        expect(snapshot.project(id)!.text('groupId'), '');
        expect(snapshot.projectClass(snapshot.project(id)!)!.id, 'se1701');
        expect(snapshot.classProjects('se1701').map((p) => p.id), contains(id));
        final list = container.read(
          managementListProvider('projects').notifier,
        );
        expect(list.visible.map((p) => p.id), contains(id));
        final after = await container.read(dashboardViewModelProvider.future);
        expect(after.activeProjects, linked.activeProjects);
        expect(
          after.activeProjects,
          snapshot
              .records('projects')
              .where(
                (p) =>
                    p.text('state') == 'active' &&
                    snapshot.projectClass(p)?.semesterId == after.semesterId,
              )
              .length,
        );
        expect(snapshot.data['reviewState'], history);
      },
    );

    test(
      'B01 selection survives group/project/class mutations and retry',
      () async {
        await container.read(dashboardViewModelProvider.future);
        final selected = repository.snapshot.semesters.last.id;
        container
            .read(dashboardViewModelProvider.notifier)
            .selectSemester(selected);
        await vm.createGroup('se1701', 'Filter retention');
        final group = repository.snapshot.groups.last;
        await vm.saveProject({
          'groupId': group.id,
          'name': 'Filter project',
          'startDate': '2026-09-01',
          'deadline': '2026-12-15T23:59',
        });
        await vm.renameGroup(group.id, 'Changed group');
        await vm.setClassState('se1701', 'active');
        expect(
          (await container.read(dashboardViewModelProvider.future)).semesterId,
          selected,
        );
        container.read(dashboardViewModelProvider.notifier).retry();
        expect(
          (await container.read(dashboardViewModelProvider.future)).semesterId,
          selected,
        );
      },
    );

    test(
      'B01 archived/deleted selection falls back to valid option; All persists',
      () async {
        await vm.saveSemester({
          'name': 'Future empty',
          'academicYear': '2027',
          'startDate': '2027-08-01',
          'endDate': '2027-12-01',
        });
        final id = repository.snapshot.semesters.last.id;
        await container.read(dashboardViewModelProvider.future);
        container.read(dashboardViewModelProvider.notifier).selectSemester(id);
        await vm.archiveSemester(id, true);
        final archived = await container.read(
          dashboardViewModelProvider.future,
        );
        expect(archived.semesterId, isNot(id));
        expect(
          archived.snapshot.semesters.map((s) => s.id),
          isNot(contains(id)),
        );
        await vm.archiveSemester(id, false);
        await container.read(dashboardViewModelProvider.future);
        container.read(dashboardViewModelProvider.notifier).selectSemester(id);
        await vm.deleteSemester(id);
        expect(
          (await container.read(dashboardViewModelProvider.future)).semesterId,
          isNot(id),
        );
        container.read(dashboardViewModelProvider.notifier).selectSemester('');
        await vm.renameGroup(
          repository.snapshot.groups.first.id,
          'All semester filter',
        );
        expect(
          (await container.read(dashboardViewModelProvider.future)).semesterId,
          '',
        );
      },
    );

    test('A02 logout revokes lease, clears user filters/saved views and reloads cache', () async {
      final oldScope = container.read(sessionScopeProvider);
      final list = container.read(managementListProvider('projects').notifier);
      list.query('private search');
      list.save('Private saved view');
      container.read(classFilterProvider.notifier).query('private class');
      await container.read(dashboardViewModelProvider.future);
      container
          .read(dashboardViewModelProvider.notifier)
          .selectSemester('spring-2027');
      await vm.saveCourse({
        'code': 'SHARED COMMITTED',
        'name': 'Shared academic data',
      });
      final oldLoads = repository.loads;
      container.read(sessionProvider.notifier).signOut();
      expect(oldScope.active, false);
      container
          .read(sessionProvider.notifier)
          .signIn('supervisor', 'b@example.test', 'demo');
      expect(container.read(sessionProvider)!.userId, 'mock:b@example.test');
      final reloaded = await container.read(academicViewModelProvider.future);
      expect(repository.loads, greaterThan(oldLoads));
      expect(reloaded.courses.any((c) => c.code == 'SHARED COMMITTED'), true);
      expect(container.read(managementListProvider('projects')).q, '');
      expect(
        container.read(managementListProvider('projects').notifier).saved,
        isEmpty,
      );
      expect(container.read(classFilterProvider).q, '');
      expect(
        (await container.read(dashboardViewModelProvider.future)).semesterId,
        reloaded.semesters.first.id,
      );
    });

    test(
      'A02 old AI completion cannot commit after logout and new login',
      () async {
        final id = repository.snapshot
            .reviewRows('requests')
            .firstWhere(
              (r) =>
                  !repository.snapshot.completed(r) &&
                  repository.snapshot.reviewRule(r)?.flag('aiEnabled') == true,
            )
            .id;
        final running = vm.runEvaluation(id);
        // Attach the error handler before the delayed completion.
        final assertion = expectLater(running, throwsA(isA<AcademicFailure>()));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final revision = repository.snapshot.revision;
        container.read(sessionProvider.notifier).signOut();
        container
            .read(sessionProvider.notifier)
            .signIn('supervisor', 'next@example.test', 'demo');
        await container.read(academicViewModelProvider.future);
        await assertion;
        expect(repository.snapshot.revision, revision);
        expect(
          container
              .read(academicViewModelProvider.notifier)
              .activeEvaluationIds,
          isEmpty,
        );
      },
    );
  });

  test(
    'B03 fake commit checks duplicate IDs/codes and stale revision atomically',
    () async {
      final service = FakeAcademicService(rootBundle);
      final original = await service.load();
      final duplicate = original.courses.first.toJson();
      for (final row in [
        duplicate,
        {...duplicate, 'id': 'different-id'},
      ]) {
        await expectLater(
          service.commit(
            original.replaceCollection('courses', [
              ...original.courses.map((c) => c.toJson()),
              row,
            ]),
            original.revision,
          ),
          throwsA(isA<AcademicFailure>()),
        );
        expect((await service.load()).toJson(), original.toJson());
      }
      await service.commit(original, original.revision);
      await expectLater(
        service.commit(original, original.revision),
        throwsA(isA<AcademicFailure>()),
      );
      expect((await service.load()).revision, original.revision + 1);
    },
  );

  test(
    'A02 fake commit checks revoked session at atomic boundary after await',
    () async {
      final gate = Completer<String>();
      final service = FakeAcademicService(_DelayedBundle(gate));
      final scope = SessionScope('user-a');
      final repository = FakeAcademicRepository(service, scope: scope);
      final original = academicFixture();
      final pending = repository.commit(
        original.replaceCollection('courses', [
          ...original.courses.map((c) => c.toJson()),
          {
            'id': 'late-private-write',
            'code': 'LATE',
            'name': 'Must not persist',
          },
        ]),
        expectedRevision: original.revision,
      );
      final assertion = expectLater(pending, throwsA(isA<AcademicFailure>()));
      scope.close();
      gate.complete(
        await rootBundle.loadString('assets/fixtures/academic.json'),
      );
      await assertion;
      expect((await service.load()).toJson(), original.toJson());
      await expectLater(repository.load(), throwsA(isA<AcademicFailure>()));
    },
  );

  test('A02 real provider repositories are replaced while shared committed data survives', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(sessionProvider.notifier);
    auth.signIn('supervisor', 'a@example.test', 'demo');
    final firstRepository = container.read(academicRepositoryProvider);
    final sharedStore = container.read(academicServiceProvider);
    await container.read(academicViewModelProvider.future);
    await container.read(academicViewModelProvider.notifier).saveCourse({
      'code': 'SHARED',
      'name': 'Saved server-like data',
    });
    final oldSession = container.read(sessionProvider)!;
    auth.signOut();
    await expectLater(firstRepository.load(), throwsA(isA<AcademicFailure>()));
    auth.signIn('supervisor', 'a@example.test', 'demo');
    expect(
      container.read(sessionProvider)!.generation,
      greaterThan(oldSession.generation),
    );
    final nextRepository = container.read(academicRepositoryProvider);
    expect(nextRepository, isNot(same(firstRepository)));
    expect(container.read(academicServiceProvider), same(sharedStore));
    final reloaded = await container.read(academicViewModelProvider.future);
    expect(reloaded.courses.where((c) => c.code == 'SHARED').length, 1);
    auth.signOut();
    auth.signIn('supervisor', 'b@example.test', 'demo');
    expect(container.read(sessionProvider)!.userId, 'mock:b@example.test');
    expect(
      container.read(academicRepositoryProvider),
      isNot(same(nextRepository)),
    );
  });

  for (final path in [
    '/projects',
    '/reviews',
    '/documents',
    '/classes',
    '/students',
  ]) {
    testWidgets('U01 sequential keyboard editing, clear and Back on $path', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final repository = TestAcademicRepository(academicFixture());
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            academicRepositoryProvider.overrideWithValue(repository),
            initialSessionProvider.overrideWithValue(
              const AppSession('supervisor'),
            ),
          ],
          child: const SrsReviewApp(),
        ),
      );
      await t.pumpAndSettle();
      final container = ProviderScope.containerOf(
        t.element(find.byType(SrsReviewApp)),
      );
      final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
      unawaited(nav.pushNamed(path));
      await t.pumpAndSettle();
      final editable = find.byType(EditableText).first;
      await t.ensureVisible(editable);
      await t.showKeyboard(editable);
      final focus = t.widget<EditableText>(editable).focusNode;
      var typed = '';
      for (final ch in 'Audit'.split('')) {
        typed += ch;
        t.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
        await t.pump();
        expect(t.widget<EditableText>(editable).focusNode, same(focus));
        expect(focus.hasFocus, true);
        expect(t.testTextInput.isVisible, true);
        expect(
          t.widget<EditableText>(editable).controller.selection.baseOffset,
          typed.length,
        );
      }
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'AuXdit',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await t.pump();
      expect(
        t.widget<EditableText>(editable).controller.selection.baseOffset,
        3,
      );
      if (path == '/classes') {
        expect(container.read(classFilterProvider).q, 'AuXdit');
        container.read(classFilterProvider.notifier).clear();
      } else if (path == '/students') {
        expect(
          container.read(studentDirectoryProvider).text('query'),
          'AuXdit',
        );
        container.read(studentDirectoryProvider.notifier).clear();
      } else {
        final kind = path.substring(1);
        final list = container.read(managementListProvider(kind).notifier);
        expect(container.read(managementListProvider(kind)).q, 'AuXdit');
        expect(list.visible, isEmpty);
        list.clear();
      }
      await t.pump();
      expect(t.widget<EditableText>(editable).controller.text, '');
      expect(focus.hasFocus, true);
      nav.pop();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'A02 session change destroys protected route stack, Back stays signed out',
    (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            academicRepositoryProvider.overrideWithValue(
              TestAcademicRepository(academicFixture()),
            ),
            initialSessionProvider.overrideWithValue(
              const AppSession('supervisor'),
            ),
          ],
          child: const SrsReviewApp(),
        ),
      );
      await t.pumpAndSettle();
      final container = ProviderScope.containerOf(
        t.element(find.byType(SrsReviewApp)),
      );
      final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
      unawaited(nav.pushNamed('/projects'));
      await t.pumpAndSettle();
      container.read(sessionProvider.notifier).signOut();
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigation), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(AppBottomNavigation), findsNothing);
      container
          .read(sessionProvider.notifier)
          .signIn('supervisor', 'next@example.test', 'demo');
      await t.pumpAndSettle();
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      expect(nav.mounted, false);
    },
  );
}

class _DelayedBundle extends CachingAssetBundle {
  _DelayedBundle(this.gate);
  final Completer<String> gate;
  @override
  Future<String> loadString(String key, {bool cache = true}) => gate.future;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}
