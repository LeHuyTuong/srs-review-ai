import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/srs_reports/domain/models/srs_report.dart';
import 'package:srs_review_ai_admin_web/features/srs_reports/data/repositories/srs_reports_repository.dart';

/// State cho SRS Reports
class SrsReportsState {
  const SrsReportsState({
    this.reports = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.statusFilter,
  });

  final List<SrsReport> reports;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String? statusFilter;

  SrsReportsState copyWith({
    List<SrsReport>? reports,
    bool? isLoading,
    String? error,
    String? searchQuery,
    String? statusFilter,
  }) {
    return SrsReportsState(
      reports: reports ?? this.reports,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }

  List<SrsReport> get filteredReports {
    var result = reports;

    if (searchQuery.isNotEmpty) {
      result = result
          .where((report) =>
              report.fileName.toLowerCase().contains(searchQuery.toLowerCase()) ||
              report.uploadedBy.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    if (statusFilter != null && statusFilter!.isNotEmpty) {
      result = result
          .where((report) => report.status == statusFilter)
          .toList();
    }

    return result;
  }
}

/// ViewModel cho SRS Reports Tab — lắng nghe Firestore stream từ repository.
class SrsReportsViewModel extends Notifier<SrsReportsState> {
  StreamSubscription<List<SrsReport>>? _subscription;

  @override
  SrsReportsState build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    _listen();
    return const SrsReportsState(isLoading: true);
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = ref.read(srsReportsRepositoryProvider).watchReports().listen(
      (reports) {
        state = state.copyWith(reports: reports, isLoading: false, error: null);
      },
      onError: (Object error) {
        debugPrint('Error loading SRS reports: $error');
        state = state.copyWith(isLoading: false, error: error.toString());
      },
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setStatusFilter(String? filter) {
    state = state.copyWith(statusFilter: filter);
  }

  Future<void> previewReport(SrsReport report) async {
    try {
      final repository = ref.read(srsReportsRepositoryProvider);
      await repository.previewReport(report);
    } catch (e) {
      debugPrint('Error previewing report: $e');
      rethrow;
    }
  }

  Future<void> downloadReport(SrsReport report) async {
    try {
      final repository = ref.read(srsReportsRepositoryProvider);
      await repository.downloadReport(report);
    } catch (e) {
      debugPrint('Error downloading report: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    _listen();
  }
}

/// Provider cho SRS Reports ViewModel
final srsReportsViewModelProvider =
    NotifierProvider<SrsReportsViewModel, SrsReportsState>(
  SrsReportsViewModel.new,
);
