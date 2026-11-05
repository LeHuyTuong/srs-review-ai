// Mô hình dự án thuần Dart cho Lab 3. Không import Firebase để kiểm thử được mà
// không cần SDK; lớp service là nơi chuyển Timestamp của Firestore sang DateTime.
enum ProjectStatus { active, archived }

class Project {
  const Project({
    required this.id,
    required this.ownerUid,
    required this.name,
    this.description = '',
    this.status = ProjectStatus.active,
    this.createdAt,
    this.updatedAt,
  });

  static const maxNameLength = 120;
  static const maxDescriptionLength = 1000;
  static const schemaVersion = 1;

  final String id;
  final String ownerUid;
  final String name;
  final String description;
  final ProjectStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isArchived => status == ProjectStatus.archived;

  static String? validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Nhập tên dự án.';
    if (trimmed.length > maxNameLength) {
      return 'Tên dự án tối đa $maxNameLength ký tự.';
    }
    return null;
  }

  static String? validateDescription(String value) {
    if (value.trim().length > maxDescriptionLength) {
      return 'Mô tả tối đa $maxDescriptionLength ký tự.';
    }
    return null;
  }

  Project copyWith({
    String? name,
    String? description,
    ProjectStatus? status,
    DateTime? updatedAt,
  }) => Project(
    id: id,
    ownerUid: ownerUid,
    name: name ?? this.name,
    description: description ?? this.description,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Dữ liệu ghi khi tạo mới. createdAt/updatedAt do service gắn serverTimestamp
  /// để Security Rules kiểm được request.time ở phía máy chủ.
  Map<String, Object?> toCreateMap() => <String, Object?>{
    'name': name.trim(),
    'description': description.trim(),
    'status': status.name,
    'ownerUid': ownerUid,
    'schemaVersion': schemaVersion,
  };

  /// Chỉ các trường nghiệp vụ được phép sửa; ownerUid và createdAt là bất biến.
  Map<String, Object?> toUpdateMap() => <String, Object?>{
    'name': name.trim(),
    'description': description.trim(),
    'status': status.name,
  };

  factory Project.fromMap(String id, Map<String, Object?> data) {
    final name = _text(data['name']);
    if (name.isEmpty) {
      throw FormatException('Dự án "$id" thiếu tên.');
    }
    final ownerUid = _text(data['ownerUid']);
    if (ownerUid.isEmpty) {
      throw FormatException('Dự án "$id" thiếu ownerUid.');
    }
    final rawStatus = _text(data['status']).isEmpty
        ? ProjectStatus.active.name
        : _text(data['status']);
    ProjectStatus? status;
    for (final value in ProjectStatus.values) {
      if (value.name == rawStatus) {
        status = value;
        break;
      }
    }
    if (status == null) {
      // Giá trị lạ phải hỏng rõ ràng, không được lặng lẽ rơi về "active".
      throw FormatException(
        'Dự án "$id" có trạng thái không hợp lệ: $rawStatus',
      );
    }
    return Project(
      id: id,
      ownerUid: ownerUid,
      name: name,
      description: _text(data['description']),
      status: status,
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    return null;
  }
}
