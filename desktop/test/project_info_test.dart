/// Round-trip tests for the project-info model against the SAME fixture the
/// schema documents (`contracts/fixtures/project_info.json`), following the
/// cross-language pattern of contract_test.dart: if the schema, the fixture
/// and the Dart model drift apart, this suite turns red.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/document_import/models/project_info.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show ContractException;

Map<String, dynamic> _fixture() {
  final file = File('../contracts/fixtures/project_info.json');
  expect(file.existsSync(), isTrue, reason: 'missing fixture ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('the schema declares the same version the model speaks', () {
    final schema =
        jsonDecode(
              File('../contracts/project-info.schema.json').readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(schema['x-contract-version'], kProjectInfoSchemaVersion);
    final properties = schema['properties'] as Map<String, dynamic>;
    final versionProp = properties['schema_version'] as Map<String, dynamic>;
    expect(versionProp['const'], kProjectInfoSchemaVersion);
  });

  test('project_info fixture parses and round-trips losslessly', () {
    final payload = _fixture();
    final info = ProjectInfo.fromJson(payload);

    expect(info.projectName, 'Online Tutor Enrollment System (OTES)');
    expect(info.students, hasLength(2));
    expect(info.students.first.fullName, 'Nguyen Van An');
    expect(info.students.first.studentId, 'SE171234');
    expect(info.supervisor, 'Dr. Le Minh Chau');
    expect(info.courseCode, 'PRM393');
    expect(info.className, 'SE1836');
    expect(info.documentVersion, '1.2');
    expect(info.submissionDate, '2026-10-15');
    expect(info.notes, isNotNull);

    // Round-trip: no field lost, none invented.
    expect(info.toJson(), payload);
  });

  test('a minimal payload (required fields only) parses', () {
    final info = ProjectInfo.fromJson({
      'schema_version': '1.0.0',
      'project_name': 'X',
      'students': [
        {'full_name': 'A', 'student_id': 'SE170001'},
      ],
    });

    expect(info.supervisor, isNull);
    expect(info.submissionDate, isNull);
    // Omitted-null serialisation keeps drafts small.
    expect(info.toJson().containsKey('supervisor'), isFalse);
  });

  test('copyWith changes only the named field', () {
    final info = ProjectInfo.fromJson(_fixture());
    final renamed = info.copyWith(projectName: 'OTES v2');

    expect(renamed.projectName, 'OTES v2');
    expect(renamed.students, same(info.students));
    expect(renamed.supervisor, info.supervisor);

    final member = info.students.first.copyWith(studentId: 'SE179999');
    expect(member.fullName, 'Nguyen Van An');
    expect(member.studentId, 'SE179999');
  });

  test('a mismatched schema version is rejected loudly', () {
    final payload = _fixture()..['schema_version'] = '0.9.0';

    expect(
      () => ProjectInfo.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('an empty team is rejected', () {
    final payload = _fixture()..['students'] = <dynamic>[];

    expect(
      () => ProjectInfo.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('a malformed student id is rejected', () {
    final payload = _fixture();
    (payload['students'] as List<dynamic>)[0] = {
      'full_name': 'Nguyen Van An',
      'student_id': 'not a roll number!',
    };

    expect(
      () => ProjectInfo.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('a malformed submission date is rejected', () {
    for (final bad in ['15/10/2026', '2026-10-15 09:00', '2026-02-30']) {
      final payload = _fixture()..['submission_date'] = bad;
      expect(
        () => ProjectInfo.fromJson(payload),
        throwsA(isA<ContractException>()),
        reason: '"$bad" must not parse',
      );
    }
  });

  test('an empty project name is rejected', () {
    final payload = _fixture()..['project_name'] = '';

    expect(
      () => ProjectInfo.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });
}
