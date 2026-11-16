import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/screens/demo_screen.dart';

void main() {
  testWidgets('Demo foundation vẫn tăng counter qua ViewModel', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DemoScreen())),
    );
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}
