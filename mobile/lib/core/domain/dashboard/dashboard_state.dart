import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_snapshot.dart';

// Số liệu được tính tại ViewModel để giao diện chỉ dựng các ô thống kê.
class DashboardStat {
  const DashboardStat(this.label, this.value);
  final String label;
  final int value;
}

// Trạng thái thành công, bao gồm cả phạm vi học kỳ không có dữ liệu.
class DashboardState {
  DashboardState({
    required this.snapshot,
    required this.semesterId,
    required List<DashboardStat> stats,
    required List<DashboardRequest> waiting,
    required List<DashboardRequest> inReview,
    required List<DashboardAttention> attention,
    required this.pendingRegistrations,
    required this.activeProjects,
    required this.archivedProjects,
    required this.needsRevision,
    required this.trackedClasses,
    required this.dueSoon,
  }) : stats = List.unmodifiable(stats),
       waiting = List.unmodifiable(waiting),
       inReview = List.unmodifiable(inReview),
       attention = List.unmodifiable(attention);

  final DashboardSnapshot snapshot;
  final String semesterId;
  final List<DashboardStat> stats;
  final List<DashboardRequest> waiting, inReview;
  final List<DashboardAttention> attention;
  final int pendingRegistrations, activeProjects, archivedProjects;
  final int needsRevision, trackedClasses, dueSoon;
  bool get isEmpty => snapshot.semesters.isEmpty;
}
