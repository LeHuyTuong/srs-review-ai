import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/di/data_providers.dart';
import 'package:srs_review_ai/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai/core/domain/session_scope.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';
import 'package:srs_review_ai/core/state/academic_changes.dart';

// Cung cấp trạng thái tải, lỗi và dữ liệu Tổng quan dùng chung cho các phần thống kê.
final dashboardViewModelProvider =
    AsyncNotifierProvider<DashboardViewModel, DashboardState>(
      DashboardViewModel.new,
      // Giữ màn lỗi ổn định cho đến khi người dùng chủ động chọn Thử lại.
      retry: (retryCount, error) => null,
    );

// Tải dữ liệu và tính thống kê đúng quan hệ học kỳ → lớp → nhóm → dự án.
class DashboardViewModel extends AsyncNotifier<DashboardState> {
  SessionScope? _scope;
  String? _selection;
  @override
  Future<DashboardState> build() async {
    ref.watch(academicChangesProvider);
    final scope = ref.watch(sessionScopeProvider);
    // Đổi phiên thì bỏ học kỳ đã chọn của phiên trước; làm mới dữ liệu trong cùng phiên vẫn giữ lựa chọn.
    if (!identical(_scope, scope)) {
      _scope = scope;
      _selection = null;
    }
    final snapshot = await ref.watch(dashboardRepositoryProvider).load();
    // Không đưa kết quả tải của phiên đã đăng xuất lên Tổng quan.
    scope.requireActive();
    final selected = _selection;
    _selection =
        selected == '' || snapshot.semesters.any((s) => s.id == selected)
        ? selected
        : snapshot.semesters.firstOrNull?.id ?? '';
    return _present(snapshot, _selection!);
  }

  // Bỏ qua ID lạ; chọn tất cả bằng chuỗi rỗng. Lọc cục bộ không gọi lại nguồn dữ liệu.
  void selectSemester(String id) {
    final current = state.asData?.value;
    if (current == null ||
        (id.isNotEmpty && !current.snapshot.semesters.any((s) => s.id == id))) {
      return;
    }
    _selection = id;
    state = AsyncData(_present(current.snapshot, id));
  }

  // Khởi tạo lại vòng tải; AsyncNotifier bỏ qua kết quả cũ sau khi bị hủy.
  void retry() => ref.invalidateSelf();

  DashboardState _present(DashboardSnapshot data, String semesterId) {
    final classes = data.classes
        .where((c) => semesterId.isEmpty || c.semesterId == semesterId)
        .toList();
    final classIds = classes.map((c) => c.id).toSet();
    final projects = data.projects
        .where((p) => classIds.contains(data.projectClassId(p)))
        .toList();
    // Chỉ dự án active mới thuộc tập cần xử lý; dự án lưu trữ vẫn được thống kê riêng.
    final activeIds = projects
        .where((p) => p.isActive)
        .map((p) => p.id)
        .toSet();
    final requests = data.requests
        .where((r) => semesterId.isEmpty || r.semesterId == semesterId)
        .toList();
    final waiting = requests
        .where((r) => r.supervisorStatus == 'waiting')
        .toList();
    final inReview = requests
        .where((r) => r.supervisorStatus == 'inReview')
        .toList();
    final attention = data.attention
        .where((a) => activeIds.contains(a.projectId))
        .toList();
    final tracked = classes.where((c) => c.isActive).toList();
    final pending = data.pendingGroupIds
        .where((id) => classIds.contains(data.groupClasses[id]))
        .length;
    // Dùng tập ID để một dự án có nhiều tài liệu/nhắc việc chỉ được tính một lần.
    final toHandle = {
      ...waiting.map((r) => r.projectId),
      ...inReview.map((r) => r.projectId),
      ...attention.map((a) => a.projectId),
    }.where(activeIds.contains).length;
    return DashboardState(
      snapshot: data,
      semesterId: semesterId,
      waiting: waiting,
      inReview: inReview,
      attention: attention,
      pendingRegistrations: pending,
      activeProjects: activeIds.length,
      archivedProjects: projects.where((p) => !p.isActive).length,
      needsRevision: requests
          .where((r) => r.supervisorStatus == 'needsRevision')
          .length,
      trackedClasses: tracked.length,
      dueSoon: attention
          .where((a) => a.label == 'Sắp đến hạn' || a.label == 'Quá hạn')
          .length,
      stats: [
        DashboardStat(
          'Môn học quản lý',
          tracked.map((c) => c.courseId).toSet().length,
        ),
        DashboardStat('Lớp đang theo dõi', tracked.length),
        DashboardStat('Tài liệu chờ đánh giá', waiting.length),
        DashboardStat('Tài liệu đang đánh giá', inReview.length),
        DashboardStat('Đăng ký chờ phản hồi', pending),
        DashboardStat('Dự án cần xử lý', toHandle),
      ],
    );
  }
}

// Giữ giới hạn tóm tắt ở ViewModel; phần còn lại được hiển thị trong khối mở rộng.
class DashboardTaskPresentation {
  const DashboardTaskPresentation(this.state);
  final DashboardState state;
  List<DashboardRequest> get preview => state.waiting.take(3).toList();
  List<DashboardRequest> get remaining => state.waiting.skip(3).toList();
}
