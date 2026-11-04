import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_radius.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_icon.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/presentation/viewmodels/crashlytics_view_model.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/domain/models/crash_log.dart';

/// Tab 2: Monitor Log Crashlytics
class CrashlyticsTab extends ConsumerWidget {
  const CrashlyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crashlyticsViewModelProvider);
    final viewModel = ref.read(crashlyticsViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Bar
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Text(
                  'Lọc theo mức độ:',
                  style: AppTypography.body,
                ),
                const SizedBox(width: AppSpacing.m),
                DropdownButton<String>(
                  value: state.filterType,
                  hint: const Text('Tất cả'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: 'fatal', child: Text('Fatal')),
                    DropdownMenuItem(value: 'non-fatal', child: Text('Non-fatal')),
                  ],
                  onChanged: (value) => viewModel.setFilterType(value),
                ),
                const Spacer(),
                AppButton(
                  label: 'Làm mới',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => viewModel.refresh(),
                  variant: AppButtonVariant.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          // Data Table
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: const BoxDecoration(
                      color: AppColors.subtle,
                      border: Border(
                        bottom: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Log ID',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Type',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Message',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'User ID',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Device Info',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Timestamp',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Chi tiết',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Table Body
                  Expanded(
                    child: state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : state.error != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Lỗi: ${state.error}',
                                      style: const TextStyle(color: AppColors.danger),
                                    ),
                                    const SizedBox(height: AppSpacing.m),
                                    AppButton(
                                      label: 'Thử lại',
                                      onPressed: () => viewModel.refresh(),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: state.filteredLogs.length,
                                itemBuilder: (context, index) {
                                  final log = state.filteredLogs[index];
                                  return _buildCrashLogRow(context, log);
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrashLogRow(BuildContext context, CrashLog log) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              log.logId,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: AppBadge(
              log.type == 'fatal' ? 'Fatal' : 'Non-fatal',
              tone: log.type == 'fatal' ? 'danger' : 'amber',
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              log.message,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              log.userId,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              log.deviceInfo,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${log.timestamp.day}/${log.timestamp.month}/${log.timestamp.year} ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
              style: AppTypography.body,
            ),
          ),
          Expanded(
            flex: 1,
            child: AppButton(
              label: 'Xem',
              icon: const Icon(Icons.visibility, size: 16),
              onPressed: () {
                _showCrashDetailDialog(context, log);
              },
              variant: AppButtonVariant.secondary,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  void _showCrashDetailDialog(BuildContext context, CrashLog log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            AppIcon(
              'circle-alert',
              color: log.type == 'fatal' ? AppColors.danger : AppColors.amber,
            ),
            const SizedBox(width: AppSpacing.s),
            Text('Chi tiết Crash - ${log.logId}'),
          ],
        ),
        content: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Loại:', log.type == 'fatal' ? 'Fatal' : 'Non-fatal'),
                _buildDetailRow('User ID:', log.userId),
                _buildDetailRow('Thiết bị:', log.deviceInfo),
                _buildDetailRow('Thời gian:', '${log.timestamp.day}/${log.timestamp.month}/${log.timestamp.year} ${log.timestamp.hour}:${log.timestamp.minute}:${log.timestamp.second}'),
                const SizedBox(height: AppSpacing.m),
                Text('Message:', style: AppTypography.strong),
                const SizedBox(height: AppSpacing.s),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    log.message,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Text('Stack Trace:', style: AppTypography.strong),
                const SizedBox(height: AppSpacing.s),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    log.stackTrace,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: AppTypography.strong),
          ),
          Expanded(
            child: Text(value, style: AppTypography.body),
          ),
        ],
      ),
    );
  }
}
