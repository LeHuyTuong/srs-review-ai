import 'package:srs_review_ai/core/domain/academic/academic_models.dart';

import 'academic_presentation_view_model.dart';

// Giữ hai phép đếm cũ: Detail hiển thị người resolve được, Card hiển thị ID đã lưu.
// Không dùng phép đếm trình bày này để thay đổi policy ghi thành viên.
class GroupPresentationViewModel {
  const GroupPresentationViewModel.detail(this.snapshot, this.group)
    : _summary = false;
  const GroupPresentationViewModel.summary(this.snapshot, this.group)
    : _summary = true;

  final AcademicSnapshot snapshot;
  final StudentGroup group;
  final bool _summary;

  ClassRoom? get classRoom => snapshot.classRoom(group.classId);
  AcademicRecord? get project => snapshot.project(group.projectId);
  List<AcademicStudent> get members =>
      AcademicPresentationViewModel(snapshot).members(group);
  int get memberCount => _summary ? group.memberIds.length : members.length;
  int get memberLimit =>
      _summary ? classRoom!.memberLimit : classRoom?.memberLimit ?? 5;
  bool get overCapacity => memberCount > memberLimit;
  bool get readOnly => classRoom?.archived != false;
  bool get canRename => !readOnly;
  bool get canDelete => !readOnly && snapshot.canDeleteGroup(group);
  bool get canCreateProject => !readOnly;
  bool get canAssignProject =>
      !readOnly &&
      AcademicPresentationViewModel(snapshot).hasAssignableProject(group);
  bool get canRemoveMember => !readOnly;
  // Nút vẫn mở biểu mẫu khi nhóm đầy; policy/biểu mẫu cũ quyết định khả năng ghi.
  bool get canAddMember => !readOnly;
  bool get showHealth => project?.text('state') != 'archived';
  AcademicJson? get health =>
      (snapshot.data['groupHealthMeta'] as AcademicJson)[group.text('health')]
          as AcademicJson?;
  String get activity =>
      ((snapshot.data['presentation'] as Map)['activities'] as Map)[group.id]
          ?.toString() ??
      group.text('lastActivity');

  String projectLabel({required bool compact}) => compact
      ? project!.text('state') == 'archived'
            ? 'Đã lưu trữ'
            : 'Đang thực hiện'
      : const {
              'active': 'Đang thực hiện',
              'archived': 'Đã lưu trữ',
              'completed': 'Hoàn thành',
              'draft': 'Bản nháp',
            }[project!.text('state')] ??
            project!.text('state');
  String projectTone({required bool compact}) => compact
      ? project!.text('state') == 'archived'
            ? 'neutral'
            : 'brand'
      : project!.text('state') == 'active'
      ? 'brand'
      : 'neutral';
}

class GroupListPresentation {
  const GroupListPresentation(this.snapshot);
  final AcademicSnapshot snapshot;
  List<GroupClassPresentation> get classes =>
      AcademicPresentationViewModel(snapshot).activeClasses
          .map((c) => GroupClassPresentation(c, snapshot.classGroups(c.id)))
          .toList();
}

class GroupClassPresentation {
  const GroupClassPresentation(this.classRoom, this.groups);
  final ClassRoom classRoom;
  final List<StudentGroup> groups;
  String get id => classRoom.id;
  String get code => classRoom.code;
  int get groupCount => groups.length;
}
