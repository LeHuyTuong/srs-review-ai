import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai/core/di/data_providers.dart';
import 'package:srs_review_ai/core/domain/counter_state.dart';

// Cung cấp trạng thái bộ đếm ví dụ qua Repository để kiểm chứng luồng Riverpod.
final counterViewModelProvider =
    NotifierProvider<CounterViewModel, CounterState>(CounterViewModel.new);

// Điều phối bộ đếm qua Repository để giao diện độc lập với bộ nhớ tạm.
class CounterViewModel extends Notifier<CounterState> {
  @override
  CounterState build() => ref.watch(counterRepositoryProvider).load();

  // Tăng bộ đếm qua nguồn dữ liệu rồi thay trạng thái bằng bản chụp bất biến.
  void increment() {
    state = ref.read(counterRepositoryProvider).increment();
  }
}
