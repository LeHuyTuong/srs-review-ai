import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/models/project.dart';
import 'package:srs_review_ai_mobile/repositories/projects_repository.dart';
import 'package:srs_review_ai_mobile/services/projects_firestore_service.dart';

class _FakeProjectsService implements ProjectsService {
  _FakeProjectsService({this.error});

  final Object? error;
  String? watchedUid;
  Project? created;
  Project? updated;
  String? deletedUid;
  String? deletedId;

  @override
  Stream<List<Project>> watchProjects(String ownerUid) {
    watchedUid = ownerUid;
    if (error != null) return Stream<List<Project>>.error(error!);
    return Stream<List<Project>>.value(const <Project>[]);
  }

  @override
  Future<String> createProject(Project project) async {
    created = project;
    return 'generated-id';
  }

  @override
  Future<void> updateProject(Project project) async {
    updated = project;
  }

  @override
  Future<void> deleteProject({
    required String ownerUid,
    required String projectId,
  }) async {
    deletedUid = ownerUid;
    deletedId = projectId;
  }
}

ProjectsRepository _repository(_FakeProjectsService service, {String? uid}) =>
    ProjectsRepository(service, () => uid);

void main() {
  test('create cắt khoảng trắng và gắn ownerUid của phiên hiện tại', () async {
    final service = _FakeProjectsService();
    final id = await _repository(
      service,
      uid: 'uid-1',
    ).create(name: '  Dự án A ', description: ' mô tả ');

    expect(id, 'generated-id');
    expect(service.created?.name, 'Dự án A');
    expect(service.created?.description, 'mô tả');
    expect(service.created?.ownerUid, 'uid-1');
  });

  test('create từ chối tên rỗng trước khi gọi Firestore', () async {
    final service = _FakeProjectsService();

    await expectLater(
      _repository(service, uid: 'uid-1').create(name: '   '),
      throwsA(isA<ProjectsFailure>()),
    );
    expect(service.created, isNull);
  });

  test('không đăng nhập thì không đọc/ghi được', () async {
    final service = _FakeProjectsService();

    await expectLater(
      _repository(service, uid: null).create(name: 'A'),
      throwsA(isA<ProjectsFailure>()),
    );
    await expectLater(
      _repository(service, uid: null).watch(),
      emitsError(isA<ProjectsFailure>()),
    );
  });

  test(
    'delete chuyển đúng ownerUid và id, không dùng uid của phiên khác',
    () async {
      final service = _FakeProjectsService();
      const project = Project(id: 'p1', ownerUid: 'uid-1', name: 'A');

      await _repository(service, uid: 'uid-2').delete(project);

      expect(service.deletedUid, 'uid-1');
      expect(service.deletedId, 'p1');
    },
  );

  test('rename kiểm tên mới trước khi ghi', () async {
    final service = _FakeProjectsService();
    const project = Project(id: 'p1', ownerUid: 'uid-1', name: 'A');

    await expectLater(
      _repository(service, uid: 'uid-1').rename(project, ''),
      throwsA(isA<ProjectsFailure>()),
    );
    expect(service.updated, isNull);
  });

  test('lỗi permission-denied được dịch thành thông báo quyền', () async {
    final service = _FakeProjectsService(
      error: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );

    await expectLater(
      _repository(service, uid: 'uid-1').watch(),
      emitsError(
        isA<ProjectsFailure>().having(
          (failure) => failure.permissionDenied,
          'permissionDenied',
          isTrue,
        ),
      ),
    );
  });
}
