import 'package:srs_review_ai_mobile/core/domain/counter_state.dart';

// Hợp đồng dữ liệu bộ đếm phục vụ kiểm chứng cách cung cấp phụ thuộc nền tảng.
abstract interface class CounterRepository {
  CounterState load();
  CounterState increment();
}
