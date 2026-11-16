// Phân biệt rõ trạng thái tải và kết quả rỗng; giao diện chỉ chọn cách trình bày.
enum ScreenPhase { loading, empty, error, data }

// Giữ nguyên phase để tương thích; lý do rỗng phân biệt nguồn, bộ lọc và entity.
enum ScreenEmptyReason { noData, filtered, notFound }

class ScreenState<T> {
  const ScreenState.loading()
    : phase = ScreenPhase.loading,
      value = null,
      emptyReason = null,
      error = null,
      stack = null;
  const ScreenState.error(this.error, this.stack)
    : phase = ScreenPhase.error,
      value = null,
      emptyReason = null;
  const ScreenState.data(
    this.value, {
    bool empty = false,
    ScreenEmptyReason emptyReason = ScreenEmptyReason.noData,
  }) : phase = empty ? ScreenPhase.empty : ScreenPhase.data,
       emptyReason = empty ? emptyReason : null,
       error = null,
       stack = null;
  final ScreenPhase phase;
  final ScreenEmptyReason? emptyReason;
  final T? value;
  final Object? error;
  final StackTrace? stack;

  R when<R>({
    required R Function() loading,
    required R Function(Object, StackTrace) error,
    required R Function(T) data,
  }) => switch (phase) {
    ScreenPhase.loading => loading(),
    ScreenPhase.error => error(this.error!, stack ?? StackTrace.empty),
    ScreenPhase.empty || ScreenPhase.data => data(value as T),
  };
}
