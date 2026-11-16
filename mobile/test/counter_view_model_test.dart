import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/counter_state.dart';
import 'package:srs_review_ai_mobile/repositories/counter_repository.dart';
import 'package:srs_review_ai_mobile/viewmodels/counter_view_model.dart';

class SeededCounterRepository implements CounterRepository {
  int count = 7;

  @override
  CounterState load() => CounterState(count: count);

  @override
  CounterState increment() => CounterState(count: ++count);
}

void main() {
  test('ViewModel loads and updates through an injected repository', () {
    final repository = SeededCounterRepository();
    final container = ProviderContainer(
      overrides: [counterRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    expect(container.read(counterViewModelProvider).count, 7);
    container.read(counterViewModelProvider.notifier).increment();
    expect(container.read(counterViewModelProvider).count, 8);
    expect(repository.count, 8);
  });

  test('default service state is scoped to each provider container', () {
    final first = ProviderContainer();
    final second = ProviderContainer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    first.read(counterViewModelProvider.notifier).increment();
    expect(first.read(counterViewModelProvider).count, 1);
    expect(second.read(counterViewModelProvider).count, 0);
  });
}
