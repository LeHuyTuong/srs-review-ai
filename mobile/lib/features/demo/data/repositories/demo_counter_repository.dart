import 'package:srs_review_ai_mobile/core/contracts/counter_repository.dart';
import 'package:srs_review_ai_mobile/core/domain/counter_state.dart';
import 'package:srs_review_ai_mobile/features/demo/data/services/demo_counter_service.dart';

// Chuyển giá trị bộ nhớ tạm thành trạng thái bộ đếm cho ViewModel.
class DemoCounterRepository implements CounterRepository {
  DemoCounterRepository(this._service);

  final DemoCounterService _service;

  @override
  CounterState load() => CounterState(count: _service.read());

  @override
  CounterState increment() {
    _service.write(_service.read() + 1);
    return load();
  }
}
