import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_icon.dart';
import 'package:srs_review_ai_admin_web/features/analytics_monitor/domain/models/analytics_event.dart';
import 'package:srs_review_ai_admin_web/features/analytics_monitor/presentation/viewmodels/analytics_view_model.dart';

/// Tab: Thống kê Analytics — đọc bản mirror sự kiện từ app mobile.
class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsViewModelProvider);
    final vm = ref.read(analyticsViewModelProvider.notifier);
    final summary = state.summary(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(days: state.days, onDays: vm.setDays),
              const SizedBox(height: AppSpacing.l),
              if (state.error != null)
                AppCard(
                  child: Row(
                    children: [
                      const AppIcon('circle-alert', color: AppColors.danger),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          'Không tải được sự kiện: ${state.error}',
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                      AppButton(label: 'Thử lại', onPressed: vm.retry),
                    ],
                  ),
                )
              else if (state.isLoading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.huge),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _KpiRow(summary: summary, wide: wide),
                const SizedBox(height: AppSpacing.l),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 7, child: _DailyChart(summary: summary)),
                        const SizedBox(width: AppSpacing.l),
                        Expanded(
                          flex: 5,
                          child: _TopEvents(
                            summary: summary,
                            filter: state.filter,
                            onTap: vm.toggleFilter,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _DailyChart(summary: summary),
                  const SizedBox(height: AppSpacing.l),
                  _TopEvents(
                    summary: summary,
                    filter: state.filter,
                    onTap: vm.toggleFilter,
                  ),
                ],
                const SizedBox(height: AppSpacing.l),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _UploadFunnel(summary: summary)),
                        const SizedBox(width: AppSpacing.l),
                        Expanded(child: _TopScreens(summary: summary)),
                      ],
                    ),
                  )
                else ...[
                  _UploadFunnel(summary: summary),
                  const SizedBox(height: AppSpacing.l),
                  _TopScreens(summary: summary),
                ],
                const SizedBox(height: AppSpacing.l),
                _RecentEvents(
                  events: state.recent,
                  filter: state.filter,
                  onClear: state.filter == null
                      ? null
                      : () => vm.toggleFilter(state.filter!),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.days, required this.onDays});
  final int days;
  final ValueChanged<int> onDays;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: AppSpacing.m,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hành vi sử dụng app mobile',
            style: AppTypography.header.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sự kiện Analytics cập nhật realtime · chỉ chứa UID, không có email/tên.',
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 1, label: Text('24 giờ')),
          ButtonSegment(value: 7, label: Text('7 ngày')),
          ButtonSegment(value: 30, label: Text('30 ngày')),
        ],
        selected: {days},
        onSelectionChanged: (s) => onDays(s.first),
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.white,
          selectedBackgroundColor: AppColors.brandSoft,
          selectedForegroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.line),
        ),
      ),
    ],
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.strong.copyWith(fontSize: 16)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: AppTypography.muted.copyWith(fontSize: 13)),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

// ───────────────────────────── KPI ─────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.summary, required this.wide});
  final AnalyticsSummary summary;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Tổng sự kiện', summary.total, 'layout-dashboard', AppColors.brand),
      ('Người dùng hoạt động', summary.activeUsers, 'users', AppColors.olive),
      ('Lượt chấm AI', summary.count('run_ai_review'), 'play', AppColors.amber),
      ('Báo cáo đã xuất', summary.count('export_report'), 'upload', AppColors.rust),
    ];
    final cards = [
      for (final (label, value, icon, color) in items)
        _Kpi(label: label, value: value, icon: icon, color: color),
    ];
    if (!wide) {
      return Wrap(
        spacing: AppSpacing.l,
        runSpacing: AppSpacing.l,
        children: [for (final c in cards) SizedBox(width: 240, child: c)],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.l),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: AppIcon(icon, color: color, size: 20),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: AppTypography.header.copyWith(fontSize: 24, height: 1.1),
              ),
              Text(
                label,
                style: AppTypography.muted.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────────── Biểu đồ theo ngày ─────────────────────────────

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final data = summary.byDay;
    final peak = data.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    final step = data.length > 14 ? 5 : 1; // nhãn thưa khi 30 ngày
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Sự kiện theo ngày',
            subtitle: summary.days == 1
                ? 'Hôm nay'
                : '${summary.days} ngày gần nhất · cao nhất $peak',
          ),
          const SizedBox(height: AppSpacing.l),
          SizedBox(
            height: 250,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < data.length; i++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${data[i].key.day}/${data[i].key.month}: ${data[i].value} sự kiện',
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: data.length > 14 ? 1.5 : 4,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (data.length <= 14 && data[i].value > 0)
                              Text(
                                '${data[i].value}',
                                style: AppTypography.muted.copyWith(fontSize: 11),
                              ),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: peak == 0
                                  ? 2
                                  : 2 + 200 * data[i].value / peak,
                              decoration: BoxDecoration(
                                color: data[i].value == 0
                                    ? AppColors.line
                                    : AppColors.brand,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: Text(
                    i % step == 0 || i == data.length - 1
                        ? '${data[i].key.day}/${data[i].key.month}'
                        : '',
                    textAlign: TextAlign.center,
                    style: AppTypography.muted.copyWith(fontSize: 11),
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Top sự kiện ─────────────────────────────

class _TopEvents extends StatelessWidget {
  const _TopEvents({
    required this.summary,
    required this.filter,
    required this.onTap,
  });
  final AnalyticsSummary summary;
  final String? filter;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final rows = summary.byName;
    final peak = rows.isEmpty ? 1 : rows.first.value;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            'Sự kiện nhiều nhất',
            subtitle: 'Bấm một dòng để lọc bảng bên dưới',
          ),
          const SizedBox(height: AppSpacing.m),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'Chưa có sự kiện trong khoảng này.',
                style: AppTypography.muted,
                textAlign: TextAlign.center,
              ),
            ),
          for (final e in rows.take(7))
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTap(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: filter == e.key ? AppColors.brandSoft : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            analyticsEventLabel(e.key),
                            style: AppTypography.body.copyWith(
                              fontWeight: filter == e.key
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value}',
                          style: AppTypography.strong.copyWith(
                            color: AppColors.brand,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: e.value / peak,
                        minHeight: 5,
                        color: AppColors.brand,
                        backgroundColor: AppColors.subtle,
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
}

// ───────────────────────────── Upload funnel ─────────────────────────────

class _UploadFunnel extends StatelessWidget {
  const _UploadFunnel({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final start = summary.count('upload_srs_start');
    final done = summary.count('upload_srs_success');
    final rate = summary.uploadSuccessRate;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Tỉ lệ upload SRS thành công',
            subtitle: 'Sinh viên bắt đầu upload bao nhiêu thì hoàn tất bao nhiêu?',
            trailing: rate == null
                ? null
                : AppBadge(
                    '${(rate * 100).round()}%',
                    tone: rate >= 0.8 ? 'brand' : 'amber',
                  ),
          ),
          const SizedBox(height: AppSpacing.l),
          _FunnelBar(label: 'Bắt đầu upload', value: start, of: start),
          const SizedBox(height: AppSpacing.m),
          _FunnelBar(label: 'Upload thành công', value: done, of: start),
          const SizedBox(height: AppSpacing.m),
          Text(
            rate == null
                ? 'Chưa có lượt upload nào trong khoảng này.'
                : '${start - done < 0 ? 0 : start - done} lượt bỏ dở hoặc lỗi.',
            style: AppTypography.muted.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar({required this.label, required this.value, required this.of});
  final String label;
  final int value;
  final int of;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 140, child: Text(label, style: AppTypography.body)),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: of == 0 ? 0 : (value / of).clamp(0, 1),
            minHeight: 22,
            color: AppColors.olive,
            backgroundColor: AppColors.subtle,
          ),
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '$value',
          textAlign: TextAlign.right,
          style: AppTypography.strong,
        ),
      ),
    ],
  );
}

// ───────────────────────────── Top màn hình ─────────────────────────────

class _TopScreens extends StatelessWidget {
  const _TopScreens({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary.topScreens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            'Màn hình được xem nhiều nhất',
            subtitle: 'Từ sự kiện screen_view (id đã ẩn thành :id)',
          ),
          const SizedBox(height: AppSpacing.m),
          if (rows.isEmpty)
            Text('Chưa có lượt xem màn hình.', style: AppTypography.muted),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: AppTypography.muted.copyWith(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].key,
                      style: AppTypography.body.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppBadge('${rows[i].value} lượt'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Bảng sự kiện ─────────────────────────────

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({
    required this.events,
    required this.filter,
    required this.onClear,
  });
  final List<AnalyticsEvent> events;
  final String? filter;
  final VoidCallback? onClear;

  String _time(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String _params(Map<String, Object?> p) =>
      p.isEmpty ? '—' : p.entries.map((e) => '${e.key}=${e.value}').join(' · ');

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(fontWeight: FontWeight.w600);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: _CardTitle(
              'Sự kiện gần nhất',
              subtitle: filter == null
                  ? '${events.length} sự kiện mới nhất'
                  : 'Đang lọc: ${analyticsEventLabel(filter!)}',
              trailing: onClear == null
                  ? null
                  : TextButton(onPressed: onClear, child: const Text('Bỏ lọc')),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.s,
            ),
            decoration: const BoxDecoration(
              color: AppColors.subtle,
              border: Border.symmetric(
                horizontal: BorderSide(color: AppColors.line),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Thời gian', style: header)),
                Expanded(flex: 3, child: Text('Sự kiện', style: header)),
                Expanded(flex: 5, child: Text('Tham số', style: header)),
                Expanded(flex: 2, child: Text('User ID', style: header)),
                Expanded(flex: 1, child: Text('Nền tảng', style: header)),
              ],
            ),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Chưa có sự kiện.',
                style: AppTypography.muted,
                textAlign: TextAlign.center,
              ),
            ),
          for (final e in events.take(30))
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.l,
                vertical: AppSpacing.s,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      _time(e.timestamp),
                      style: AppTypography.muted.copyWith(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppBadge(
                        e.name,
                        tone: switch (e.name) {
                          'login' || 'logout' => 'olive',
                          'run_ai_review' || 'submit_review_decision' => 'amber',
                          'export_report' ||
                          'upload_srs_success' ||
                          'upload_srs_start' => 'rust',
                          'trigger_test_crash' => 'danger',
                          'screen_view' => 'neutral',
                          _ => 'brand',
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      _params(e.params),
                      style: AppTypography.body.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      e.userId.isEmpty
                          ? '—'
                          : '${e.userId.substring(0, e.userId.length.clamp(0, 10))}…',
                      style: AppTypography.muted.copyWith(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      e.platform,
                      style: AppTypography.muted.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    );
  }
}
