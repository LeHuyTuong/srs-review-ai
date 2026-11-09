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
                      hintText: 'Tìm kiếm theo tên tài liệu hoặc người tải lên...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => viewModel.setSearchQuery(value),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(
                      labelText: 'Trạng thái',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: state.statusFilter,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Tất cả')),
                      DropdownMenuItem<String?>(value: 'pending', child: Text('Chờ duyệt')),
                      DropdownMenuItem<String?>(value: 'reviewed', child: Text('Đã xem xét')),
                      DropdownMenuItem<String?>(value: 'approved', child: Text('Đã phê duyệt')),
                      DropdownMenuItem<String?>(value: 'rejected', child: Text('Từ chối')),
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
                          flex: 3,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Tên tài liệu',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Dung lượng',
                              style: TextStyle(fontWeight: FontWeight.w600),
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Người tải lên',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Ngày tạo',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Trạng thái',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                            child: Text(
                              'Thao tác',
                              style: TextStyle(fontWeight: FontWeight.w600),
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
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Row(
                children: [
                  const AppIcon('file-text', color: AppColors.brand, size: 20),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Tooltip(
                      message: report.fileName,
                      child: Text(
                        report.fileName,
                        style: AppTypography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                report.fileSizeFormatted,
                style: AppTypography.body,
                softWrap: false,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    report.uploaderDisplayName,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.uploaderSubtitle,
                    style: AppTypography.muted.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Text(
                '${report.uploadDate.day}/${report.uploadDate.month}/${report.uploadDate.year} ${report.uploadDate.hour}:${report.uploadDate.minute.toString().padLeft(2, '0')}',
                style: AppTypography.body,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      label: 'Xem',
                      icon: const Icon(Icons.visibility, size: 16),
                      onPressed: () async {
                        try {
                          await viewModel.previewReport(report);
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
                    const SizedBox(width: AppSpacing.s),
                    AppButton(
                      label: 'Tải',
                      icon: const Icon(Icons.download, size: 16),
                      onPressed: () async {
                        try {
                          await viewModel.downloadReport(report);
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
            ),
          ),
        ],
      ),
    );
  }
}
