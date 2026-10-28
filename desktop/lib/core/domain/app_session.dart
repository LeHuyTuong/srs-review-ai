// Phiên đăng nhập mô phỏng, dự kiến thay bằng Google Sign-In khi tích hợp Firebase.
// Chỉ nhận vai trò Supervisor, kể cả khi khôi phục phiên từ dữ liệu bên ngoài.
class AppSession {
  const AppSession(
    this.role, {
    this.userId = 'mock-supervisor',
    this.generation = 0,
  });
  final String role;
  final String userId;
  final int generation;
  bool get isSupervisor => role == 'supervisor';
}
