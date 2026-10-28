import 'package:srs_review_ai/core/domain/dashboard/dashboard_snapshot.dart';

// Hợp đồng độc lập với nguồn dữ liệu để thay kho mô phỏng bằng Repository thật sau này.
abstract interface class DashboardRepository {
  Future<DashboardSnapshot> load();
}
