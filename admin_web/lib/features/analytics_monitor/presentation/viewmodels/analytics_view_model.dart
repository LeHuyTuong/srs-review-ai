import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/analytics_monitor/data/repositories/analytics_repository.dart';
import 'package:srs_review_ai_admin_web/features/analytics_monitor/domain/models/analytics_event.dart';

class AnalyticsState {
  const AnalyticsState({
    this.events = const [],
    this.days = 7,
    this.filter,
    this.isLoading = true,
    this.error,
  });

  final List<AnalyticsEvent> events;
  final int days;
  final String? filter;
  final bool isLoading;
  final String? error;

  AnalyticsSummary summary(DateTime now) =>
      AnalyticsSummary.from(events, now: now, days: days);

  List<AnalyticsEvent> get recent => [
    for (final e in events)
      if (filter == null || e.name == filter) e,
  ].take(100).toList();

  AnalyticsState copyWith({
    List<AnalyticsEvent>? events,
    int? days,
    String? Function()? filter,
    bool? isLoading,
    String? Function()? error,
  }) => AnalyticsState(
    events: events ?? this.events,
    days: days ?? this.days,
    filter: filter != null ? filter() : this.filter,
    isLoading: isLoading ?? this.isLoading,
    error: error != null ? error() : this.error,
  );
}

/// Lắng nghe realtime `analytics_events` theo khoảng thời gian đang chọn.
class AnalyticsViewModel extends Notifier<AnalyticsState> {
  StreamSubscription<List<AnalyticsEvent>>? _sub;

  @override
  AnalyticsState build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(() => _listen(7));
    return const AnalyticsState();
  }

  void _listen(int days) {
    _sub?.cancel();
    final since = DateTime.now().subtract(Duration(days: days));
    _sub = ref
        .read(analyticsRepositoryProvider)
        .watchEvents(since: since)
        .listen(
          (events) => state = state.copyWith(
            events: events,
            isLoading: false,
            error: () => null,
          ),
          onError: (Object e) => state = state.copyWith(
            isLoading: false,
            error: () => e.toString(),
          ),
        );
  }

  void setDays(int days) {
    if (days == state.days) return;
    state = state.copyWith(days: days, isLoading: true);
    _listen(days);
  }

  /// Bấm lại đúng sự kiện đang lọc thì bỏ lọc.
  void toggleFilter(String name) => state = state.copyWith(
    filter: () => state.filter == name ? null : name,
  );

  void retry() {
    state = state.copyWith(isLoading: true, error: () => null);
    _listen(state.days);
  }
}

final analyticsViewModelProvider =
    NotifierProvider<AnalyticsViewModel, AnalyticsState>(AnalyticsViewModel.new);
