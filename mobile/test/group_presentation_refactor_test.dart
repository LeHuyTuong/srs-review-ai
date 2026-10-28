import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/group_presentation_view_model.dart';

import 'support/academic_fixture.dart';

void main() {
  test('Group detail and summary retain their distinct member counts', () {
    final source = academicFixture().toJson();
    final groups = (source['groups'] as List).cast<Map<String, dynamic>>();
    final rawGroup = groups.firstWhere(
      (group) => group['id'] == 'se1701-group-01',
    );
    rawGroup['memberIds'] = [...rawGroup['memberIds'] as List, 'missing-id'];
    final snapshot = AcademicSnapshot(source);
    final group = snapshot.group('se1701-group-01')!;

    expect(GroupPresentationViewModel.detail(snapshot, group).memberCount, 4);
    expect(GroupPresentationViewModel.summary(snapshot, group).memberCount, 5);
  });

  test('Archived group presentation disables management actions', () {
    final source = academicFixture().toJson();
    final classes = (source['classes'] as List).cast<Map<String, dynamic>>();
    classes.firstWhere((c) => c['id'] == 'se1701')['state'] = 'archived';
    final snapshot = AcademicSnapshot(source);
    final group = snapshot.group('se1701-group-01')!;
    final presentation = GroupPresentationViewModel.detail(snapshot, group);

    expect(presentation.readOnly, isTrue);
    expect(presentation.canRename, isFalse);
    expect(presentation.canDelete, isFalse);
    expect(presentation.canCreateProject, isFalse);
    expect(presentation.canAssignProject, isFalse);
    expect(presentation.canRemoveMember, isFalse);
    expect(presentation.canAddMember, isFalse);
  });
}
