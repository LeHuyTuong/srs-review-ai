import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_admin_web/app/app_web.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/data/repositories/crashlytics_repository.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/domain/models/crash_log.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/data/repositories/srs_reports_repository.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/domain/models/srs_report.dart';
import 'package:srs_review_ai_admin_web/features/users_management/data/repositories/users_repository.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

void main() {
  testWidgets('Admin Web renders the master-detail shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          usersRepositoryProvider.overrideWithValue(_FakeUsersRepository()),
          crashlyticsRepositoryProvider.overrideWithValue(
            _FakeCrashlyticsRepository(),
          ),
          srsReportsRepositoryProvider.overrideWithValue(
            _FakeSrsReportsRepository(),
          ),
        ],
        child: const SrsReviewAiWebApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SRS Admin'), findsOneWidget);
    expect(find.text('Quản lý Báo cáo SRS'), findsWidgets);
  });
}

class _FakeUsersRepository implements UsersRepository {
  @override
  Stream<List<AppUser>> watchUsers() => Stream.value(const []);
}

class _FakeCrashlyticsRepository implements CrashlyticsRepository {
  @override
  Stream<List<CrashLog>> watchCrashLogs() => Stream.value(const []);
}

class _FakeSrsReportsRepository implements SrsReportsRepository {
  @override
  Stream<List<SrsReport>> watchReports() => Stream.value(const []);

  @override
  Future<String> resolveDownloadUrl(SrsReport report) async =>
      report.downloadUrl;

  @override
  Future<void> previewReport(SrsReport report) async {}

  @override
  Future<void> downloadReport(SrsReport report) async {}
}
