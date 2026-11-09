import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';

/// Background callback phải là top-level để Flutter có thể khôi phục isolate.
/// Thông báo do server gửi đã có trong inbox; ở đây chỉ ghi thông báo ngoài
/// server (Console) để danh sách trong app không thiếu.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId ?? '(no id)'}');
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await recordPushInInbox(FirestorePushInboxRepository(), uid, message);
}

/// Ghi thông báo vào inbox nếu server chưa ghi (không có `inboxId`).
Future<void> recordPushInInbox(
  PushInboxRepository inbox,
  String uid,
  RemoteMessage message, {
  bool read = false,
}) async {
  if (message.data['inboxId'] != null) return;
  final title = message.notification?.title;
  final body = message.notification?.body;
  if (title == null && body == null) return;
  final id =
      message.messageId ??
      'local-${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}';
  try {
    await inbox.record(uid, id, {
      'title': title ?? '',
      'body': body ?? '',
      'type': message.data['type']?.toString() ?? '',
      'targetId': message.data['id']?.toString() ?? '',
      'source': 'device',
      'read': read,
    });
  } catch (e) {
    debugPrint('FCM inbox record error: $e');
  }
}

/// Ghi/xoá token của một user; mặc định là Firestore `users/{uid}.fcmTokens`.
abstract class FcmTokenStore {
  Future<void> add(String uid, String token);
  Future<void> remove(String uid, String token);
}

class FirestoreFcmTokenStore implements FcmTokenStore {
  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  @override
  Future<void> add(String uid, String token) => _doc(uid).set({
    'fcmTokens': FieldValue.arrayUnion([token]),
    'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  @override
  Future<void> remove(String uid, String token) => _doc(uid).set({
    'fcmTokens': FieldValue.arrayRemove([token]),
  }, SetOptions(merge: true));
}

/// Nhận thông báo và chỉ điều hướng tới các route nghiệp vụ đã biết.
class FcmService {
  FcmService({
    FirebaseMessaging? messaging,
    GlobalKey<NavigatorState>? navigatorKey,
    FcmTokenStore? tokenStore,
    Stream<String?>? userIds,
    PushInboxRepository? inbox,
  }) : _providedMessaging = messaging,
       _navigatorKey = navigatorKey ?? appNavigatorKey,
       _providedStore = tokenStore,
       _providedUserIds = userIds,
       _providedInbox = inbox;

  final PushInboxRepository? _providedInbox;
  PushInboxRepository get _inbox =>
      _providedInbox ?? FirestorePushInboxRepository();

  final FcmTokenStore? _providedStore;
  FcmTokenStore get _store => _providedStore ?? FirestoreFcmTokenStore();
  final Stream<String?>? _providedUserIds;
  Stream<String?> get _userIds =>
      _providedUserIds ??
      FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);
  StreamSubscription<String?>? _userSubscription;
  StreamSubscription<String>? _tokenSubscription;
  String? _uid;
  String? _token;

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

    // Web cần service worker + VAPID key; chưa cấu hình thì bỏ qua token
    // thay vì để getToken ném lỗi chặn khởi động.
    if (!kIsWeb) {
      try {
        // ignore: deprecated_member_use
        _token = await _messaging.getToken();
      } catch (e) {
        debugPrint('FCM getToken error: $e');
      }
      // ignore: deprecated_member_use
      _tokenSubscription = _messaging.onTokenRefresh.listen((value) {
        _token = value;
        _saveToken();
      });
    }
    _listenUser();

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      showForeground,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _openMessage(initialMessage);
  }

  void _listenUser() {
    _userSubscription ??= _userIds.listen((uid) {
      _uid = uid;
      if (!kIsWeb) _saveToken();
    });
  }

  /// Test bật listener UID mà không cần plugin FCM thật.
  @visibleForTesting
  void debugListenUser() => _listenUser();

  Future<void> _saveToken() async {
    final uid = _uid, token = _token;
    if (uid == null || token == null) return;
    try {
      await _store.add(uid, token);
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  /// Gọi TRƯỚC khi signOut (sau signOut Firestore không còn quyền ghi), để máy
  /// dùng chung không tiếp tục nhận thông báo của người vừa đăng xuất.
  Future<void> unregisterCurrentUser() async {
    final uid = _uid, token = _token;
    if (uid == null || token == null) return;
    try {
      await _store.remove(uid, token).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('FCM token remove error: $e');
    }
  }

  /// Khi app đang mở, hệ điều hành không tự hiện notification → hiện SnackBar.
  @visibleForTesting
  void showForeground(RemoteMessage message) {
    final uid = _uid;
    if (uid != null) unawaited(recordPushInInbox(_inbox, uid, message));
    final context = _navigatorKey.currentContext;
    final messenger = context == null
        ? null
        : ScaffoldMessenger.maybeOf(context);
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (messenger == null || (title == null && body == null)) return;
    final route = _routeFor(message.data);
    messenger.showSnackBar(
      SnackBar(
        content: Text([?title, ?body].join('\n')),
        action: route == null
            ? null
            : SnackBarAction(
                label: 'Mở',
                onPressed: () => _navigatorKey.currentState?.pushNamed(route),
              ),
      ),
    );
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
    unawaited(_markOpened(message));
    final route = _routeFor(message.data);
    if (route == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingRoute = route;
    } else {
      navigator.pushNamed(route);
    }
  }

  /// Bấm notification hệ thống = đã đọc. Lúc app vừa mở từ trạng thái tắt,
  /// auth có thể chưa khôi phục xong nên chờ UID đầu tiên.
  Future<void> _markOpened(RemoteMessage message) async {
    final uid =
        _uid ??
        await _userIds
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (uid == null) return;
    final inboxId = message.data['inboxId']?.toString();
    try {
      if (inboxId != null) {
        await _inbox.markRead(uid, inboxId);
      } else {
        await recordPushInInbox(_inbox, uid, message, read: true);
      }
    } catch (e) {
      debugPrint('FCM inbox mark-read error: $e');
    }
  }

  String? _routeFor(Map<String, dynamic> data) => pushRouteFor(data);

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _userSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}

// Key dùng chung để xử lý click từ notification kể cả khi không có BuildContext.
final appNavigatorKey = GlobalKey<NavigatorState>();
final fcmService = FcmService(navigatorKey: appNavigatorKey);
