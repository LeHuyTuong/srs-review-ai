import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/models/project.dart';

void main() {
  group('Project.validateName', () {
    test('từ chối tên rỗng hoặc chỉ có khoảng trắng', () {
      expect(Project.validateName(''), isNotNull);
      expect(Project.validateName('   '), isNotNull);
    });

    test('từ chối tên dài hơn giới hạn', () {
      final tooLong = 'a' * (Project.maxNameLength + 1);
      expect(Project.validateName(tooLong), isNotNull);
    });

    test('chấp nhận tên hợp lệ', () {
      expect(Project.validateName('  Hệ thống quản lý học tập '), isNull);
    });
  });

  test('fromMap đọc đủ trường và giữ trạng thái lưu trữ', () {
    final project = Project.fromMap('p1', <String, Object?>{
      'name': 'Dự án A',
      'description': 'Mô tả',
      'status': 'archived',
      'ownerUid': 'uid-1',
      'createdAt': DateTime.utc(2026, 11, 5),
      'updatedAt': DateTime.utc(2026, 11, 6),
    });

    expect(project.id, 'p1');
    expect(project.name, 'Dự án A');
    expect(project.ownerUid, 'uid-1');
    expect(project.isArchived, isTrue);
    expect(project.createdAt, DateTime.utc(2026, 11, 5));
  });

  test('fromMap ném FormatException khi thiếu ownerUid', () {
    expect(
      () => Project.fromMap('p1', <String, Object?>{'name': 'A'}),
      throwsFormatException,
    );
  });

  test(
    'fromMap ném FormatException khi trạng thái lạ, không rơi về active',
    () {
      expect(
        () => Project.fromMap('p1', <String, Object?>{
          'name': 'A',
          'ownerUid': 'uid-1',
          'status': 'deleted',
        }),
        throwsFormatException,
      );
    },
  );

  test('toCreateMap không tự gắn timestamp để Rules kiểm request.time', () {
    const project = Project(id: '', ownerUid: 'uid-1', name: ' A ');
    final map = project.toCreateMap();

    expect(map['name'], 'A');
    expect(map['ownerUid'], 'uid-1');
    expect(map['status'], 'active');
    expect(map['schemaVersion'], Project.schemaVersion);
    expect(map.containsKey('createdAt'), isFalse);
    expect(map.containsKey('updatedAt'), isFalse);
  });

  test('copyWith giữ nguyên ownerUid và createdAt', () {
    final created = DateTime.utc(2026, 1, 1);
    final project = Project(
      id: 'p1',
      ownerUid: 'uid-1',
      name: 'A',
      createdAt: created,
    );
    final renamed = project.copyWith(name: 'B', status: ProjectStatus.archived);

    expect(renamed.name, 'B');
    expect(renamed.status, ProjectStatus.archived);
    expect(renamed.ownerUid, 'uid-1');
    expect(renamed.createdAt, created);
  });
}
