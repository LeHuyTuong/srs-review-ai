import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/services/fcm_service.dart';

class _Store implements FcmTokenStore {
  final log = <String>[];
  @override
  Future<void> add(String uid, String token) async => log.add('add $uid $token');
  @override
  Future<void> remove(String uid, String token) async =>
      log.add('remove $uid $token');
}

void main() {
  testWidgets('foreground message shows a SnackBar that opens its route',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final service = FcmService(navigatorKey: key, tokenStore: _Store());
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      onGenerateRoute: (s) => MaterialPageRoute<void>(
          settings: s, builder: (_) => Scaffold(body: Text('at ${s.name}'))),
    ));
    service.showForeground(const RemoteMessage(
      notification: RemoteNotification(title: 'Đã chấm', body: 'Xem kết quả'),
      data: {'type': 'review', 'id': 'r9'},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Đã chấm\nXem kết quả'), findsOneWidget);
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(find.text('at /reviews/r9'), findsOneWidget);
  });

  testWidgets('data-only message shows nothing', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final service = FcmService(navigatorKey: key, tokenStore: _Store());
    await tester.pumpWidget(MaterialApp(
        navigatorKey: key, home: const Scaffold(body: SizedBox())));
    service.showForeground(const RemoteMessage(data: {'type': 'review'}));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}
