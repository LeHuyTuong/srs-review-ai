import 'package:flutter/material.dart';

// Hiển thị giá trị bộ đếm nền tảng mà không tự quản lý trạng thái.
class DemoCounterValue extends StatelessWidget {
  const DemoCounterValue({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) =>
      Text('$count', style: Theme.of(context).textTheme.headlineMedium);
}
