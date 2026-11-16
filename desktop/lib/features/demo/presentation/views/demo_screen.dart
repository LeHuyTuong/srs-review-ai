import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai/features/demo/presentation/viewmodels/counter_view_model.dart';
import 'package:srs_review_ai/widgets/demo_counter_value.dart';

// Màn ví dụ bộ đếm được giữ lại để kiểm chứng nền tảng Flutter.
class DemoScreen extends ConsumerWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(counterViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Demo nền tảng Flutter')),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Số lần nhấn nút:'),
              DemoCounterValue(count: state.count),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: ref.read(counterViewModelProvider.notifier).increment,
        tooltip: 'Tăng số đếm',
        child: const Icon(Icons.add),
      ),
    );
  }
}
