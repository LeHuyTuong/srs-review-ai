import 'package:srs_review_ai_mobile/core/state/academic_changes.dart';
import 'package:srs_review_ai_mobile/features/demo/data/repositories/demo_counter_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:srs_review_ai_mobile/features/dashboard/data/services/fake_dashboard_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/dashboard/dashboard_repository.dart';
import 'package:srs_review_ai_mobile/features/dashboard/data/repositories/fake_dashboard_repository.dart';
import 'package:srs_review_ai_mobile/features/dashboard/data/repositories/firestore_dashboard_repository.dart';

import 'package:srs_review_ai_mobile/core/contracts/counter_repository.dart';
import 'package:srs_review_ai_mobile/features/demo/data/services/demo_counter_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/fake_academic_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/data/repositories/fake_academic_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/data/repositories/firestore_academic_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/student_device_gateway.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/student_import_service.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/sync/offline_academic_store.dart';

final firebaseInitializedProvider = Provider<bool>(
  (ref) => Firebase.apps.isNotEmpty,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

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

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  if (!ref.watch(firebaseInitializedProvider)) {
    return FakeDashboardRepository(ref.watch(dashboardServiceProvider));
  }
  return FirestoreDashboardRepository(
    ref.watch(firestoreAcademicServiceProvider),
  );
});

// SQLite trên máy. Mặc định `null` (web, flutter test): kho chỉ nằm trong RAM
// như trước. `main.dart` mở DB trên Android/iOS rồi override provider này.
final offlineAcademicStoreProvider = Provider<OfflineAcademicStore?>(
  (ref) => null,
);

// Kho dùng chung giữ dữ liệu đã lưu khi phiên đăng nhập kết thúc.
final academicServiceProvider = Provider<FakeAcademicService>(
  (ref) => FakeAcademicService(
    rootBundle,
    persistence: ref.watch(offlineAcademicStoreProvider),
  ),
);

/// Shared Firestore service for live academic data and the dashboard projection.
final firestoreAcademicServiceProvider = Provider<FirebaseAcademicService>(
  (ref) =>
      FirebaseAcademicService(
          ref.watch(firebaseInitializedProvider)
              ? ref.watch(firestoreProvider)
              : null,
          syncOutbox: ref.watch(offlineAcademicStoreProvider),
        )
        ..onRemoteChange = () =>
            ref.read(academicRemoteChangesProvider.notifier).applied(),
);
// Tách thao tác chọn tệp và sao chép khỏi ViewModel để thay thế được khi kiểm thử.
final studentImportServiceProvider = Provider<StudentDeviceGateway>(
  (ref) => StudentImportService(),
);
// Tạo Repository theo phạm vi phiên hiện tại, còn kho dữ liệu mô phỏng được dùng chung.
final academicRepositoryProvider = Provider<AcademicRepository>((ref) {
  final scope = ref.watch(sessionScopeProvider);
  // Widget tests and pre-Firebase startup retain the fixture implementation;
  // a Firebase-initialized app always reads and writes through Firestore.
  if (!ref.watch(firebaseInitializedProvider)) {
    return FakeAcademicRepository(
      ref.watch(academicServiceProvider),
      scope: scope,
    );
  }
  return FirestoreAcademicRepository(
    ref.watch(firestoreAcademicServiceProvider),
    scope: scope,
  );
});
