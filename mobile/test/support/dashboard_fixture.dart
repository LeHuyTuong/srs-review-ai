import 'dart:convert';
import 'dart:io';

import 'package:srs_review_ai_mobile/models/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/repositories/dashboard/dashboard_repository.dart';

DashboardSnapshot loadFixture() => DashboardSnapshot.fromJson(
  jsonDecode(File('assets/fixtures/dashboard.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// Repository kiểm thử cho phép điều khiển thành công/lỗi mà không sửa fixture UI.
class TestDashboardRepository implements DashboardRepository {
  TestDashboardRepository(this.result);
  Future<DashboardSnapshot> Function() result;
  int calls = 0;
  @override
  Future<DashboardSnapshot> load() {
    calls++;
    return result();
  }
}
