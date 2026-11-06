import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/dashboard/dashboard_repository.dart';

/// Firestore dashboard source. Derives the same JSON shape as the fixture
/// path, but from the realtime academic stream so progress stats update
/// live (Luồng 3).
class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository(this._service);

  final FirebaseAcademicService _service;

  /// Backend kiểm thử trong bộ nhớ khi Firebase chưa khởi tạo (chỉ test gọi).
  void enableOnNullBackend() => _service.enableTestBackend();

  @override
  Future<DashboardSnapshot> load() async {
    final snapshot = await _service.load();
    return DashboardSnapshot.fromJson(snapshot.dashboardJson);
  }

  @override
  Stream<DashboardSnapshot> watch() => _service.watch().map(
    (snapshot) => DashboardSnapshot.fromJson(snapshot.dashboardJson),
  );
}
