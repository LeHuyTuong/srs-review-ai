import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';

const reviewSchedulePath = '/review-schedule';
const groupQuestionsPath = '/group-questions';

class _ReviewScheduleItem {
  const _ReviewScheduleItem({
    required this.dateTime,
    required this.group,
    required this.project,
    required this.purpose,
  });

  final String dateTime;
  final String group;
  final String project;
  final String purpose;
}

class _GroupQuestionItem {
  const _GroupQuestionItem({
    required this.group,
    required this.project,
    required this.sentAt,
    required this.question,
  });

  final String group;
  final String project;
  final String sentAt;
  final String question;
}

const _reviewScheduleItems = [
  _ReviewScheduleItem(
    dateTime: '03/11/2026 · 09:00',
    group: 'Nhóm 03 · SE1701',
    project: 'Hệ thống quản lý học tập',
    purpose: 'Review tài liệu SRS',
  ),
  _ReviewScheduleItem(
    dateTime: '05/11/2026 · 14:00',
    group: 'Nhóm 04 · SE1701',
    project: 'Ứng dụng quản lý câu lạc bộ',
    purpose: 'Hướng dẫn tiến độ đề tài',
  ),
];

const _groupQuestionItems = [
  _GroupQuestionItem(
    group: 'Nhóm 03 · SE1701',
    project: 'Hệ thống quản lý học tập',
    sentAt: '30/10/2026 · 10:15',
    question: 'Nhóm cần làm rõ phạm vi của chức năng đăng ký học phần.',
  ),
  _GroupQuestionItem(
    group: 'Nhóm 04 · SE1701',
    project: 'Ứng dụng quản lý câu lạc bộ',
    sentAt: '29/10/2026 · 16:20',
    question: 'Nhóm hỏi về các trường hợp ngoại lệ khi hủy sự kiện.',
  ),
];

class DashboardFollowUpPreviews extends StatelessWidget {
  const DashboardFollowUpPreviews({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.m,
    children: [
      _FollowUpPreview(
        title: 'Lịch review sắp tới',
        detail:
            '${_reviewScheduleItems.first.dateTime} · ${_reviewScheduleItems.first.group}',
        path: reviewSchedulePath,
        actionLabel: 'Xem tất cả lịch',
        onTap: () => onNavigate(reviewSchedulePath),
      ),
      _FollowUpPreview(
        title: 'Câu hỏi từ nhóm',
        detail:
            '${_groupQuestionItems.first.group} · ${_groupQuestionItems.first.question}',
        path: groupQuestionsPath,
        actionLabel: 'Xem tất cả câu hỏi',
        onTap: () => onNavigate(groupQuestionsPath),
      ),
    ],
  );
}

class _FollowUpPreview extends StatelessWidget {
  const _FollowUpPreview({
    required this.title,
    required this.detail,
    required this.path,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String detail;
  final String path;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.blockTitle)),
            const AppBadge('Minh họa', tone: 'amber'),
          ],
        ),
        Text(
          detail,
          style: AppTypography.muted,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        TextButton(
          key: ValueKey('dashboard-follow-up-$path'),
          onPressed: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(actionLabel),
          ),
        ),
      ],
    ),
  );
}

class ReviewScheduleScreen extends StatelessWidget {
  const ReviewScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) => AcademicPage(
    path: reviewSchedulePath,
    showBackButton: true,
    builder: (_) => [
      const AppPageHeading(
        eyebrow: 'TỔNG QUAN · LỊCH',
        title: 'Lịch review',
        description: 'Các buổi review và hướng dẫn của nhóm.',
      ),
      const AppNotice(
        'Dữ liệu minh họa để xem giao diện, không phải lịch thực tế.',
      ),
      for (final item in _reviewScheduleItems)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s,
            children: [
              Text(item.dateTime, style: AppTypography.strong),
              Text(item.group, style: AppTypography.muted),
              Text(item.project, style: AppTypography.blockTitle),
              Text(item.purpose, style: AppTypography.muted),
            ],
          ),
        ),
    ],
  );
}

class GroupQuestionsScreen extends StatelessWidget {
  const GroupQuestionsScreen({super.key});

  @override
  Widget build(BuildContext context) => AcademicPage(
    path: groupQuestionsPath,
    showBackButton: true,
    builder: (_) => [
      const AppPageHeading(
        eyebrow: 'TỔNG QUAN · CÂU HỎI',
        title: 'Câu hỏi từ nhóm',
        description: 'Các câu hỏi nhóm gửi giảng viên cần xem.',
      ),
      const AppNotice(
        'Dữ liệu minh họa, không phải câu hỏi thực tế. Danh sách chỉ để xem, chưa có thao tác trả lời.',
      ),
      for (final item in _groupQuestionItems)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s,
            children: [
              Text(item.group, style: AppTypography.strong),
              Text(item.project, style: AppTypography.muted),
              Text(item.question),
              Text('Gửi lúc ${item.sentAt}', style: AppTypography.muted),
            ],
          ),
        ),
    ],
  );
}
