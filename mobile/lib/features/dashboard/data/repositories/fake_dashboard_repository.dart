import 'package:srs_review_ai_mobile/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/features/dashboard/data/services/fake_dashboard_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/dashboard/dashboard_repository.dart';

// Chuyển dữ liệu mẫu sang mô hình Tổng quan, không cấp quyền hay quyết định đánh giá.
class FakeDashboardRepository implements DashboardRepository {
  const FakeDashboardRepository(this._service);
  final FakeDashboardService _service;

  @override
  Future<DashboardSnapshot> load() async =>
      DashboardSnapshot.fromJson(await _service.load());
}
