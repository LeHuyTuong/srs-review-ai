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
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(
                      labelText: 'Lọc theo mức độ',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: state.filterType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Tất cả')),
                      DropdownMenuItem<String?>(value: 'fatal', child: Text('Chỉ lỗi nghiêm trọng')),
                      DropdownMenuItem<String?>(value: 'non-fatal', child: Text('Chỉ cảnh báo')),
                    ],
                    onChanged: (value) => viewModel.setFilterType(value),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                      vertical: AppSpacing.s,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.subtle,
                      border: Border(
                        bottom: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Mã sự cố',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Mức độ',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Thông báo lỗi',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Người dùng',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Thiết bị',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Thời gian',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Chi tiết',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
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
    final userId = log.userId.trim();
    final hasUserId = userId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.m,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Tooltip(
                message: log.logId,
                child: Text(
                  log.logId,
                  style: AppTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppBadge(
                  log.type == 'fatal' ? 'Nghiêm trọng' : 'Cảnh báo',
                  tone: log.type == 'fatal' ? 'danger' : 'amber',
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Tooltip(
                message: log.message,
                child: Text(
                  log.message,
                  style: AppTypography.body,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: hasUserId
                  ? Tooltip(
                      message: userId,
                      child: Text(
                        userId,
                        style: AppTypography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : Text(
                      '—',
                      style: AppTypography.body.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                log.deviceInfo.isNotEmpty ? log.deviceInfo : '—',
                style: AppTypography.body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                '${log.timestamp.day}/${log.timestamp.month}/${log.timestamp.year} ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                style: AppTypography.body,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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
              ),
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
            Text('Chi tiết sự cố - ${log.logId}'),
          ],
        ),
        content: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Mức độ:', log.type == 'fatal' ? 'Nghiêm trọng' : 'Cảnh báo'),
                _buildDetailRow('User ID:', log.userId.isNotEmpty ? log.userId : '— (Chưa đăng nhập)'),
                _buildDetailRow('Thiết bị:', log.deviceInfo.isNotEmpty ? log.deviceInfo : '—'),
                _buildDetailRow('Thời gian:', '${log.timestamp.day}/${log.timestamp.month}/${log.timestamp.year} ${log.timestamp.hour}:${log.timestamp.minute}:${log.timestamp.second}'),
                const SizedBox(height: AppSpacing.m),
                Text('Nội dung lỗi:', style: AppTypography.strong),
                const SizedBox(height: AppSpacing.s),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: SelectableText(
                    log.message,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Text('Truy vết lỗi (Stack Trace):', style: AppTypography.strong),
                const SizedBox(height: AppSpacing.s),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: SelectableText(
                    log.stackTrace.isNotEmpty ? log.stackTrace : 'Không có stack trace',
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
