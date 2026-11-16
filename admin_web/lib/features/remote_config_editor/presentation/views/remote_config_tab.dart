import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/features/remote_config_editor/presentation/viewmodels/remote_config_view_model.dart';
import 'package:srs_review_ai_admin_web/features/remote_config_editor/domain/models/remote_config_param.dart';

/// Tab 3: Cấu hình Tham số từ xa
class RemoteConfigTab extends ConsumerWidget {
  const RemoteConfigTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteConfigViewModelProvider);
    final viewModel = ref.read(remoteConfigViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Publish button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cấu hình tải lên SRS',
                      style: AppTypography.header.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Phát hành giới hạn dung lượng và định dạng tệp SRS '
                      'lên hệ thống cấu hình từ xa.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: state.isPublishing
                    ? 'Đang phát hành...'
                    : 'Lưu & Phát hành',
                icon: state.isPublishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload, size: 18),
                onPressed: state.hasChanges && !state.isPublishing
                    ? () async {
                        final success = await viewModel.publishChanges();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Đã phát hành cấu hình thành công.'
                                    : (viewModel.lastPublishError != null
                                        ? 'Lỗi khi phát hành: ${viewModel.lastPublishError}'
                                        : 'Lỗi khi phát hành cấu hình'),
                              ),
                              backgroundColor: success
                                  ? AppColors.olive
                                  : AppColors.danger,
                            ),
                          );
                        }
                      }
                    : null,
              ),
              const SizedBox(width: AppSpacing.s),
              AppButton(
                label: 'Làm mới',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => viewModel.refresh(),
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Thay đổi được phát hành tới ứng dụng di động. Hệ thống chỉ cho phép các tài khoản quản trị viên thực hiện.',
              style: AppTypography.body.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          // Parameters List
          Expanded(
            child: AppCard(
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
                  : ListView.separated(
                      itemCount: state.parameters.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: AppSpacing.xl,
                        color: AppColors.line,
                      ),
                      itemBuilder: (context, index) {
                        final param = state.parameters[index];
                        return _buildParameterItem(context, ref, param);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tên tiếng Việt thân thiện cho từng tham số, che key kỹ thuật khỏi UI.
  String _titleFor(RemoteConfigParam param) => switch (param.key) {
    'max_upload_file_size_mb' => 'Dung lượng tệp tải lên tối đa (MB)',
    'allowed_srs_file_types' => 'Định dạng tệp SRS được phép',
    _ => param.description,
  };

  String _subtitleFor(RemoteConfigParam param) => switch (param.key) {
    'max_upload_file_size_mb' =>
      'Ứng dụng sẽ từ chối tệp lớn hơn giới hạn này khi sinh viên chọn tệp.',
    'allowed_srs_file_types' =>
      'Nhập định dạng tệp cách nhau bằng dấu phẩy: pdf,docx,md.',
    _ => param.description,
  };

  String _defaultLabel(dynamic value) =>
      value is bool ? (value ? 'Bật' : 'Tắt') : '$value';

  Widget _buildParameterItem(
    BuildContext context,
    WidgetRef ref,
    RemoteConfigParam param,
  ) {
    final viewModel = ref.read(remoteConfigViewModelProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleFor(param),
                    style: AppTypography.strong.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _subtitleFor(param),
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Text(
              'Mặc định: ${_defaultLabel(param.defaultValue)}',
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        if (param.type == 'boolean')
          Row(
            children: [
              Text('Giá trị hiện tại:', style: AppTypography.body),
              const SizedBox(width: AppSpacing.m),
              Switch(
                value: param.currentValue as bool,
                onChanged: (value) =>
                    viewModel.updateParameter(param.key, value),
                activeThumbColor: AppColors.brand,
              ),
              const SizedBox(width: AppSpacing.s),
              Text(
                param.currentValue as bool ? 'Bật' : 'Tắt',
                style: AppTypography.body,
              ),
            ],
          )
        else if (param.type == 'number')
          Row(
            children: [
              Text('Giá trị hiện tại:', style: AppTypography.body),
              const SizedBox(width: AppSpacing.m),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: param.currentValue.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                      vertical: AppSpacing.s,
                    ),
                  ),
                  onChanged: (value) {
                    final numValue = num.tryParse(value);
                    if (numValue != null) {
                      viewModel.updateParameter(param.key, numValue);
                    }
                  },
                ),
              ),
              if (param.minValue != null && param.maxValue != null) ...[
                const SizedBox(width: AppSpacing.m),
                Text(
                  '(Từ ${param.minValue} đến ${param.maxValue})',
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              Text('Giá trị hiện tại:', style: AppTypography.body),
              const SizedBox(width: AppSpacing.m),
              SizedBox(
                width: 300,
                child: TextFormField(
                  initialValue: param.currentValue.toString(),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                      vertical: AppSpacing.s,
                    ),
                  ),
                  onChanged: (value) {
                    viewModel.updateParameter(param.key, value);
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}
