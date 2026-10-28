import 'package:srs_review_ai_mobile/features/demo/data/repositories/demo_counter_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:srs_review_ai_mobile/features/dashboard/data/services/fake_dashboard_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/dashboard/dashboard_repository.dart';
import 'package:srs_review_ai_mobile/features/dashboard/data/repositories/fake_dashboard_repository.dart';

import 'package:srs_review_ai_mobile/core/contracts/counter_repository.dart';
import 'package:srs_review_ai_mobile/features/demo/data/services/demo_counter_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/fake_academic_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/data/repositories/fake_academic_repository.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/student_device_gateway.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/student_import_service.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';

// Nơi cung cấp các phụ thuộc: giao diện và ViewModel không tự tạo nguồn dữ liệu cụ thể.
final demoCounterServiceProvider = Provider<DemoCounterService>(
  (ref) => DemoCounterService(),
);

final counterRepositoryProvider = Provider<CounterRepository>(
  (ref) => DemoCounterRepository(ref.watch(demoCounterServiceProvider)),
);

// Tổng quan đọc cùng Repository học vụ để thống kê phản ánh các thay đổi đã lưu.
final dashboardServiceProvider = Provider<FakeDashboardService>((ref) {
  final repository = ref.watch(academicRepositoryProvider);
  return FakeDashboardService(
    rootBundle,
    loadData: () async => (await repository.load()).dashboardJson,
  );
});

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FakeDashboardRepository(ref.watch(dashboardServiceProvider)),
);

// Kho mô phỏng dùng chung giữ dữ liệu đã lưu khi phiên đăng nhập kết thúc.
final academicServiceProvider = Provider<FakeAcademicService>(
  (ref) => FakeAcademicService(rootBundle),
);
// Tách thao tác chọn tệp và sao chép khỏi ViewModel để thay thế được khi kiểm thử.
final studentImportServiceProvider = Provider<StudentDeviceGateway>(
  (ref) => StudentImportService(),
);
// Tạo Repository theo phạm vi phiên hiện tại, còn kho dữ liệu mô phỏng được dùng chung.
final academicRepositoryProvider = Provider<AcademicRepository>(
  (ref) => FakeAcademicRepository(
    ref.watch(academicServiceProvider),
    scope: ref.watch(sessionScopeProvider),
  ),
);
