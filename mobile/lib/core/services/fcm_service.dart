import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';

/// Background callback phải là top-level để Flutter có thể khôi phục isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId ?? '(no id)'}');
}

/// Nhận thông báo và chỉ điều hướng tới các route nghiệp vụ đã biết.
class FcmService {
  FcmService({
    FirebaseMessaging? messaging,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : _providedMessaging = messaging,
       _navigatorKey = navigatorKey ?? appNavigatorKey;

  final FirebaseMessaging? _providedMessaging;
  FirebaseMessaging get _messaging =>
      _providedMessaging ?? FirebaseMessaging.instance;
  final GlobalKey<NavigatorState> _navigatorKey;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  String? _pendingRoute;

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('FCM notification permission: ${settings.authorizationStatus}');

    // User cần FCM Token (FCM installation id trong onRegistered không thay thế token này).
    // ignore: deprecated_member_use
    final token = await _messaging.getToken();
    if (token != null) debugPrint('FCM Token: $token');
    // ignore: deprecated_member_use
    _messaging.onTokenRefresh.listen(
      (value) => debugPrint('FCM Token: $value'),
    );

    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId ?? '(no id)'}');
    });
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _openMessage(initialMessage);
  }

  void attachNavigator() {
    final route = _pendingRoute;
    if (route == null) return;
    _pendingRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.pushNamed(route);
    });
  }

  void _openMessage(RemoteMessage message) {
    final route = _routeFor(message.data);
    if (route == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingRoute = route;
    } else {
      navigator.pushNamed(route);
    }
  }

  String? _routeFor(Map<String, dynamic> data) {
    final kind = data['type']?.toString();
    final id = data['id']?.toString();
    return switch (kind) {
      'review' when id != null && id.isNotEmpty =>
        '/reviews/${Uri.encodeComponent(id)}',
      'notification' => '/notifications',
      'course' when id != null && id.isNotEmpty =>
        '/courses/${Uri.encodeComponent(id)}',
      _ => null,
    };
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}

// Key dùng chung để xử lý click từ notification kể cả khi không có BuildContext.
final appNavigatorKey = GlobalKey<NavigatorState>();
final fcmService = FcmService(navigatorKey: appNavigatorKey);
