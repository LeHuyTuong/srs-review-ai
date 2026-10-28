import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';

// Các lựa chọn của màn hình thuộc ViewModel và được khởi tạo lại khi đổi phiên.
class AcademicUiState {
  const AcademicUiState({this.tab = 0, this.library = false});
  final int tab;
  final bool library;
}

final academicUiProvider = NotifierProvider.autoDispose
    .family<AcademicUiViewModel, AcademicUiState, String>(
      AcademicUiViewModel.new,
    );

class AcademicUiViewModel extends Notifier<AcademicUiState> {
  AcademicUiViewModel(this.key);
  final String key;
  @override
  AcademicUiState build() {
    ref.watch(sessionScopeProvider);
    return AcademicUiState(tab: key.startsWith('class:') ? 1 : 0);
  }

  void tab(int value) =>
      state = AcademicUiState(tab: value, library: state.library);
  void library(bool value) =>
      state = AcademicUiState(tab: state.tab, library: value);
}

// Mỗi lần mở bảng lọc có định danh riêng, hủy bảng không ghi bộ lọc đang áp dụng.
class FilterDraftSpec {
  const FilterDraftSpec(this.initial);
  final Map<String, List<String>> initial;
}

final filterDraftProvider = NotifierProvider.autoDispose
    .family<FilterDraftViewModel, Map<String, List<String>>, FilterDraftSpec>(
      FilterDraftViewModel.new,
    );

class FilterDraftViewModel extends Notifier<Map<String, List<String>>> {
  FilterDraftViewModel(this.spec);
  final FilterDraftSpec spec;
  @override
  Map<String, List<String>> build() {
    ref.watch(sessionScopeProvider);
    return {...spec.initial};
  }

  void clear() => state = {};
  void set(String key, List<String> value) => state = {...state, key: value};
}
