/// Model đại diện cho người dùng
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.registrationDate,
    required this.lastSignIn,
    required this.role,
    this.deviceCount = 0,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final DateTime registrationDate;
  final DateTime lastSignIn;
  /// Số thiết bị đã đăng ký nhận push (`users/{uid}.fcmTokens`).
  final int deviceCount;
  final String role; // 'teacher', 'student', 'admin' (hoặc giá trị tiếng Việt cũ)

  /// Chuẩn hoá để đọc được cả role canonical lẫn dữ liệu cũ/tiếng Việt.
  String get normalizedRole => role.trim().toLowerCase();

  bool get isAdminRole => normalizedRole == 'admin';

  bool get isTeacherRole => const {
    'teacher',
    'supervisor',
    'lecturer',
    'giảng viên',
    'giang vien',
  }.contains(normalizedRole);

  bool get isStudentRole => const {
    'student',
    'sinh viên',
    'sinh vien',
  }.contains(normalizedRole);

  String get roleLabel {
    if (isAdminRole) return 'Admin';
    if (isTeacherRole) return 'Giảng viên';
    if (isStudentRole) return 'Sinh viên';
    final trimmed = role.trim();
    return trimmed.isEmpty ? 'Chưa xác định' : trimmed;
  }

  AppUser copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    DateTime? registrationDate,
    DateTime? lastSignIn,
    String? role,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      registrationDate: registrationDate ?? this.registrationDate,
      lastSignIn: lastSignIn ?? this.lastSignIn,
      role: role ?? this.role,
    );
  }
}
