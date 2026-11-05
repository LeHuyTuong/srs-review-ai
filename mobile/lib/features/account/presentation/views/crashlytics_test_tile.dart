import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/services/crashlytics_support.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/settings_view_model.dart';

/// Khu vực demo Lab 3. Đặt widget này vào màn hình Settings/Account.
class CrashlyticsTestTile extends ConsumerWidget {
  const CrashlyticsTestTile({super.key});

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kiểm thử Crashlytics'),
        content: const Text(
          'Ứng dụng sẽ đóng đột ngột để gửi báo cáo crash thử nghiệm. '
          'Chỉ dùng khi demo. Tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gây crash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsViewModelProvider).runTestCrash();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supportsCrashlytics) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('Kiểm thử Crashlytics'),
      subtitle: const Text('Khu vực demo – gây crash có chủ đích'),
      onTap: () => _onPressed(context, ref),
    );
  }
}
