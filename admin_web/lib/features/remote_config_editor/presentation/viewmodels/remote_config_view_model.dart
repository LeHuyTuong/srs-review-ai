import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/remote_config_editor/domain/models/remote_config_param.dart';
import 'package:srs_review_ai_admin_web/features/remote_config_editor/data/repositories/remote_config_repository.dart';

/// State cho Remote Config
class RemoteConfigState {
  const RemoteConfigState({
    this.parameters = const [],
    this.isLoading = false,
    this.isPublishing = false,
    this.error,
    this.hasChanges = false,
  });

  final List<RemoteConfigParam> parameters;
  final bool isLoading;
  final bool isPublishing;
  final String? error;
  final bool hasChanges;

  RemoteConfigState copyWith({
    List<RemoteConfigParam>? parameters,
    bool? isLoading,
    bool? isPublishing,
    String? error,
    bool? hasChanges,
  }) {
    return RemoteConfigState(
      parameters: parameters ?? this.parameters,
      isLoading: isLoading ?? this.isLoading,
      isPublishing: isPublishing ?? this.isPublishing,
      error: error,
      hasChanges: hasChanges ?? this.hasChanges,
    );
  }
}

/// ViewModel cho Remote Config Tab
class RemoteConfigViewModel extends Notifier<RemoteConfigState> {
  String? lastPublishError;
  @override
  RemoteConfigState build() {
    _loadParameters();
    return const RemoteConfigState(isLoading: true);
  }

  Future<void> _loadParameters() async {
    try {
      final repository = ref.read(remoteConfigRepositoryProvider);
      final parameters = await repository.getParameters();
      state = state.copyWith(
        parameters: parameters,
        isLoading: false,
        error: null,
        hasChanges: false,
      );
    } catch (e) {
      debugPrint('Error loading remote config: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void updateParameter(String key, dynamic value) {
    final updatedParams = state.parameters.map((param) {
      if (param.key == key) {
        return param.copyWith(currentValue: value);
      }
      return param;
    }).toList();

    state = state.copyWith(
      parameters: updatedParams,
      hasChanges: true,
    );
  }

  Future<bool> publishChanges() async {
    try {
      state = state.copyWith(isPublishing: true);
      final repository = ref.read(remoteConfigRepositoryProvider);
      await repository.publishParameters(state.parameters);
      
      // Reload to sync with server
      final parameters = await repository.getParameters();
      state = state.copyWith(
        parameters: parameters,
        isPublishing: false,
        hasChanges: false,
        error: null,
      );
      return true;
    } catch (e) {
      debugPrint('Error publishing remote config: $e');
      lastPublishError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      state = state.copyWith(
        isPublishing: false,
      );
      return false;
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadParameters();
  }
}

/// Provider cho Remote Config ViewModel
final remoteConfigViewModelProvider =
    NotifierProvider<RemoteConfigViewModel, RemoteConfigState>(
  RemoteConfigViewModel.new,
);
