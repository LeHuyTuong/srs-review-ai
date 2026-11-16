import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';

class _Recorder implements AnalyticsService {
  final calls = <String>[];
  @override
  Future<void> logScreenView(String s) async => calls.add('screen:$s');
  @override
  Future<void> logSelectContent({
    required String contentType,
    required String itemId,
  }) async => calls.add('$contentType:$itemId');
  @override
  Future<void> logViewSrsDetail({
    required String documentId,
    required String category,
  }) async => calls.add('srs:$documentId:$category');
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

void main() {
  test('screen name hides ids', () {
    expect(AnalyticsRouteObserver.screenNameFor('/reviews/r1/ai-result'),
        '/reviews/:id/ai-result');
    expect(AnalyticsRouteObserver.screenNameFor('/'), '/dashboard');
  });

  testWidgets('push logs business event, pop logs only screen_view',
      (tester) async {
    final rec = _Recorder();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [AnalyticsRouteObserver(rec)],
      onGenerateRoute: (s) => MaterialPageRoute<void>(
          settings: s, builder: (_) => Text(s.name ?? '')),
      initialRoute: '/courses',
    ));
    key.currentState!.pushNamed('/courses/c1');
    await tester.pumpAndSettle();
    key.currentState!.pushNamed('/reviews/r9');
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rec.calls, [
      'screen:/courses', // '/' và '/courses' cùng frame khởi động → một lượt
      'course:c1', 'screen:/courses/:id',
      'srs:r9:review', 'screen:/reviews/:id',
      'screen:/courses/:id',
    ]);
  });

  testWidgets('popUntil logs a single screen_view for the screen left on top',
      (tester) async {
    final rec = _Recorder();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [AnalyticsRouteObserver(rec)],
      onGenerateRoute: (s) => MaterialPageRoute<void>(
          settings: s, builder: (_) => Text(s.name ?? '')),
    ));
    key.currentState!.pushNamed('/projects');
    await tester.pumpAndSettle();
    key.currentState!.pushNamed('/reviews');
    await tester.pumpAndSettle();
    rec.calls.clear();
    key.currentState!.popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    expect(rec.calls, ['screen:/dashboard']);
  });
}
