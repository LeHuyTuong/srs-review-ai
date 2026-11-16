import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';

const _labels = ['Tất cả', 'Chưa đọc', 'Đánh giá', 'Hạn nộp', 'Đánh giá AI'];

Future<bool> _redAt(WidgetTester tester, GlobalKey key, double x) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final width = boundary.size.width;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = (x < 0 ? width + x : x).round();
    final i = ((boundary.size.height ~/ 2) * image.width + px) * 4;
    // Mép mờ để lộ nền đỏ: đỏ trội hẳn so với xanh lá.
    return data.getUint8(i) > 150 && data.getUint8(i + 1) < 120;
  }))!;
}

Future<GlobalKey> _pump(WidgetTester tester, double width) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: width,
          child: Material(
            color: const Color(0xFFFF0000),
            child: AppTabs(labels: _labels, selected: 0, onChanged: (_) {}, segmented: true),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return key;
}

void main() {
  testWidgets('a tab strip wider than the screen fades the edge that hides more tabs', (tester) async {
    final key = await _pump(tester, 300);
    expect(await _redAt(tester, key, -2), isTrue, reason: 'right edge hides tabs, so it fades');
    expect(await _redAt(tester, key, 2), isFalse, reason: 'nothing is hidden on the left yet');

    await tester.drag(find.byType(SingleChildScrollView), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(await _redAt(tester, key, 2), isTrue, reason: 'scrolled: the left edge now hides tabs');
    expect(await _redAt(tester, key, -2), isFalse, reason: 'at the end nothing is hidden on the right');
  });
}
