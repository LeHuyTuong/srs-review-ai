import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_icon.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_text_input.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/presentation/viewmodels/srs_reports_view_model.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/domain/models/srs_report.dart';

/// Tab 1: Quản lý Báo cáo SRS
class SrsReportsTab extends ConsumerWidget {
  const SrsReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(srsReportsViewModelProvider);
    final viewModel = ref.read(srsReportsViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search and Filter Bar
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: AppTextInput(
                    decoration: const InputDecoration(
                      hintText: 'Tìm kiếm theo tên file hoặc người upload...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => viewModel.setSearchQuery(value),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Trạng thái',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: state.statusFilter,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tất cả')),
                      DropdownMenuItem(value: 'pending', child: Text('Chờ duyệt')),
                      DropdownMenuItem(value: 'reviewed', child: Text('Đã xem xét')),
                      DropdownMenuItem(value: 'approved', child: Text('Đã phê duyệt')),
                      DropdownMenuItem(value: 'rejected', child: Text('Từ chối')),
                    ],
                    onChanged: (value) => viewModel.setStatusFilter(value),
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
                          flex: 3,
                          child: Text(
                            'Tên file',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Dung lượng',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Người upload',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Ngày tạo',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Trạng thái',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Thao tác',
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
                                itemCount: state.filteredReports.length,
                                itemBuilder: (context, index) {
                                  final report = state.filteredReports[index];
                                  return _buildReportRow(context, ref, report);
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

  Widget _buildReportRow(BuildContext context, WidgetRef ref, SrsReport report) {
    final viewModel = ref.read(srsReportsViewModelProvider.notifier);
    
    String statusText;
    switch (report.status) {
      case 'pending':
        statusText = 'Chờ duyệt';
        break;
      case 'reviewed':
        statusText = 'Đã xem xét';
        break;
      case 'approved':
        statusText = 'Đã phê duyệt';
        break;
      case 'rejected':
        statusText = 'Từ chối';
        break;
      default:
        statusText = report.status;
    }

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
            flex: 3,
            child: Row(
              children: [
                const AppIcon('file-text', color: AppColors.brand, size: 20),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    report.fileName,
                    style: AppTypography.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              report.fileSizeFormatted,
              style: AppTypography.body,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              report.uploadedBy,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${report.uploadDate.day}/${report.uploadDate.month}/${report.uploadDate.year} ${report.uploadDate.hour}:${report.uploadDate.minute.toString().padLeft(2, '0')}',
              style: AppTypography.body,
            ),
          ),
          Expanded(
            flex: 1,
            child: AppBadge(
              statusText,
              tone: report.status == 'approved'
                  ? 'olive'
                  : report.status == 'rejected'
                      ? 'danger'
                      : report.status == 'pending'
                          ? 'amber'
                          : 'brand',
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                AppButton(
                  label: 'Xem',
                  icon: const Icon(Icons.visibility, size: 16),
                  onPressed: () async {
                    try {
                      await viewModel.previewReport(report);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Đang mở ${report.fileName}')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  variant: AppButtonVariant.secondary,
                  compact: true,
                ),
                AppButton(
                  label: 'Tải',
                  icon: const Icon(Icons.download, size: 16),
                  onPressed: () async {
                    try {
                      await viewModel.downloadReport(report);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Đã tải ${report.fileName}')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Lỗi: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  variant: AppButtonVariant.secondary,
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
