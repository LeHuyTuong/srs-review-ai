import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/domain/models/crash_log.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/data/repositories/crashlytics_repository.dart';

/// State cho Crashlytics
class CrashlyticsState {
  const CrashlyticsState({
    this.logs = const [],
    this.isLoading = false,
    this.error,
    this.filterType, // 'fatal', 'non-fatal', or null for all
  });

  final List<CrashLog> logs;
  final bool isLoading;
  final String? error;
  final String? filterType;

  CrashlyticsState copyWith({
    List<CrashLog>? logs,
    bool? isLoading,
    String? error,
    String? filterType,
  }) {
    return CrashlyticsState(
      logs: logs ?? this.logs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      filterType: filterType ?? this.filterType,
    );
  }

  List<CrashLog> get filteredLogs {
    if (filterType == null || filterType!.isEmpty) {
      return logs;
    }
    return logs.where((log) => log.type == filterType).toList();
  }
}

/// ViewModel cho Crashlytics Tab — lắng nghe Firestore stream từ repository.
class CrashlyticsViewModel extends Notifier<CrashlyticsState> {
  StreamSubscription<List<CrashLog>>? _subscription;

  @override
  CrashlyticsState build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    _listen();
    return const CrashlyticsState(isLoading: true);
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = ref
        .read(crashlyticsRepositoryProvider)
        .watchCrashLogs()
        .listen(
          (logs) {
            state = state.copyWith(logs: logs, isLoading: false, error: null);
          },
          onError: (Object error) {
            debugPrint('Error loading crash logs: $error');
            state = state.copyWith(isLoading: false, error: error.toString());
          },
        );
  }

  void setFilterType(String? type) {
    state = state.copyWith(filterType: type);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    _listen();
  }
}

/// Provider cho Crashlytics ViewModel
final crashlyticsViewModelProvider =
    NotifierProvider<CrashlyticsViewModel, CrashlyticsState>(
  CrashlyticsViewModel.new,
);
