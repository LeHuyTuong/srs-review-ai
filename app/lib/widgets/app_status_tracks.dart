import 'package:flutter/material.dart';

import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';

// Nhãn trạng thái lấy từ dữ liệu mô tả; giữ nhãn gọn khi cột cha giãn ngang.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge(this.status, {required this.snapshot, super.key});
  final String status;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final meta = (snapshot.data['statusMeta'] as Map)[status] as Map?;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: AppBadge(
        meta?['label']?.toString() ??
            const {
              'active': 'Đang thực hiện',
              'archived': 'Đã lưu trữ',
              'notStarted': 'Chưa bắt đầu',
              'submissionLocked': 'Khóa gửi đánh giá',
            }[status] ??
            status,
        tone:
            meta?['tone']?.toString() ??
            (status == 'active' ? 'brand' : 'neutral'),
      ),
    );
  }
}

// Ba luồng trạng thái độc lập: tài liệu, đề xuất AI và quyết định giảng viên.
// Không suy ra approved từ kết quả AI.
class AppStatusTracks extends StatelessWidget {
  const AppStatusTracks({
    required this.snapshot,
    required this.documentStatus,
    this.review,
    this.supervisorStatus,
    super.key,
  });
  final AcademicSnapshot snapshot;
  final AcademicRecord? review;
  final String documentStatus;
  final String? supervisorStatus;
  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.muted),
        Flexible(child: value),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        row('Tài liệu', AppStatusBadge(documentStatus, snapshot: snapshot)),
        row(
          'AI đề xuất',
          Text(
            review == null
                ? 'AI chưa có kết quả'
                : ReviewPolicy.aiLabel(snapshot, review!),
            textAlign: TextAlign.right,
            style: AppTypography.muted,
          ),
        ),
        row(
          'Giảng viên',
          supervisorStatus == null || supervisorStatus!.isEmpty
              ? const AppBadge('Chưa có yêu cầu')
              : AppStatusBadge(supervisorStatus!, snapshot: snapshot),
        ),
      ],
    );
  }
}
