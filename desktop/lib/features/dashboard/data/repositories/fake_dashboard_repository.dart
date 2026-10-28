import 'package:srs_review_ai/core/contracts/dashboard/dashboard_repository.dart';
import 'package:srs_review_ai/core/domain/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai/features/dashboard/data/services/fake_dashboard_service.dart';

// Chuyển dữ liệu mẫu sang mô hình Tổng quan, không cấp quyền hay quyết định đánh giá.
class FakeDashboardRepository implements DashboardRepository {
  const FakeDashboardRepository(this._service);
  final FakeDashboardService _service;

  @override
  Future<DashboardSnapshot> load() async =>
      DashboardSnapshot.fromJson(await _service.load());
}
