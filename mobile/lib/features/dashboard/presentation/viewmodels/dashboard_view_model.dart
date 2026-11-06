import 'package:srs_review_ai_mobile/core/state/academic_changes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_state.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/domain/session_scope.dart';
import 'package:srs_review_ai_mobile/features/account/data/repositories/current_user_repository.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/current_user_view_model.dart';

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
  DashboardSnapshot? _raw;

  // Dashboard projection may contain the original fixture identity. The
  // signed-in Firebase profile is the source of truth for the greeting.
  DashboardSnapshot _withProfile(
    DashboardSnapshot snapshot,
    CurrentUserProfile? profile,
  ) {
    if (profile == null || profile.displayName.trim().isEmpty) {
      return snapshot;
    }
    return snapshot.withUser(
      userName: profile.displayName,
      role: profile.roleLabel,
    );
  }
  @override
  Future<DashboardState> build() async {
    ref.watch(academicChangesProvider);
    ref.watch(academicRemoteChangesProvider);
    final scope = ref.watch(sessionScopeProvider);
    // Đổi phiên thì bỏ học kỳ đã chọn của phiên trước; làm mới dữ liệu trong cùng phiên vẫn giữ lựa chọn.
    if (!identical(_scope, scope)) {
      _scope = scope;
      _selection = null;
    }
    // Hồ sơ đổi chỉ cập nhật lời chào; không tải lại repository (watch ở đây
    // từng làm mỗi lần hồ sơ về tới lại gọi load() thêm một lần).
    ref.listen(currentUserProvider, (_, next) {
      final raw = _raw, current = state.asData?.value;
      if (raw == null || current == null) return;
      state = AsyncData(
        _present(_withProfile(raw, next.asData?.value), current.semesterId),
      );
    });
    final raw = await ref.watch(dashboardRepositoryProvider).load();
    // Không đưa kết quả tải của phiên đã đăng xuất lên Tổng quan.
    scope.requireActive();
    _raw = raw;
    final snapshot = _withProfile(
      raw,
      ref.read(currentUserProvider).asData?.value,
    );
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
