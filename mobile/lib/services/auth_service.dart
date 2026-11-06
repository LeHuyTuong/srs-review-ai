import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:srs_review_ai_mobile/core/firestore/firestore_collections.dart';
import 'package:srs_review_ai_mobile/firebase_options.dart';

/// Hàm khởi tạo Google Sign-In, seam để test không cần SDK thật.
typedef GoogleSignInInitializer = Future<void> Function({
  String? clientId,
  String? serverClientId,
});

/// Tham số khởi tạo Google Sign-In cho một nền tảng.
class GoogleSignInInit {
  const GoogleSignInInit({this.clientId, this.serverClientId});

  final String? clientId;
  final String? serverClientId;
}

/// Chọn tham số khởi tạo theo nền tảng.
///
/// google_sign_in_web chỉ nhận `clientId` và assert `serverClientId` phải null;
/// native thì ngược lại, cần `serverClientId`.
GoogleSignInInit resolveGoogleSignInInit({
  required bool isWeb,
  String? webClientId,
}) {
  if (isWeb) {
    if (webClientId == null || webClientId.isEmpty) {
      throw StateError(
        'Thiếu OAuth client id cho Google Sign-In trên web. Chạy '
        '"python tools/flutter_env.py mobile prepare" để sinh lại cấu hình.',
      );
    }
    return GoogleSignInInit(clientId: webClientId);
  }
  return GoogleSignInInit(
    serverClientId: DefaultFirebaseOptions.googleSignInServerClientId,
  );
}

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    this.firestore,
    GoogleSignInInitializer? googleInitializer,
  }) : _firebaseAuth = auth,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _googleInitializer =
           googleInitializer ??
           (googleSignIn ?? GoogleSignIn.instance).initialize;

  final FirebaseAuth? _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final GoogleSignInInitializer _googleInitializer;
  final FirebaseFirestore? firestore;

  /// GoogleSignIn.instance là singleton và google_sign_in_web chỉ cho gọi
  /// init() một lần trong một lần tải trang, nên future này ở mức static.
  static Future<void>? _googleInitialization;

  /// Xoá cache khởi tạo. Chỉ dùng trong test.
  @visibleForTesting
  static void resetGoogleInitialization() {
    _googleInitialization = null;
  }

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Đăng nhập Google trên native.
  ///
  /// `google_sign_in_web` không hỗ trợ `authenticate()`, nên web đi đường khác:
  /// xem [webSignInEvents] và [completeWebSignIn].
  Future<User?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    try {
      final googleUser = await _googleSignIn.authenticate();
      return await _signInToFirebase(googleUser.authentication.idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  /// Web: sự kiện đăng nhập do nút GSI của plugin phát ra.
  Stream<GoogleSignInAccount> get webSignInEvents => _googleSignIn
      .authenticationEvents
      .where((event) => event is GoogleSignInAuthenticationEventSignIn)
      .map((event) => (event as GoogleSignInAuthenticationEventSignIn).user);

  /// Web: đổi tài khoản Google do nút GSI trả về thành phiên Firebase.
  Future<User?> completeWebSignIn(GoogleSignInAccount account) async {
    await _ensureGoogleInitialized();
    return _signInToFirebase(account.authentication.idToken);
  }

  /// Đổi ID token của Google thành phiên Firebase Auth.
  Future<User?> _signInToFirebase(String? idToken) async {
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google Sign-In không trả về ID token.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final user = (await _auth.signInWithCredential(credential)).user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-firebase-user',
        message: 'Firebase Authentication không trả về người dùng.',
      );
    }
    await _syncUserProfile(user);
    return user;
  }

  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } finally {
      await _auth.signOut();
    }
  }

  /// Upsert hồ sơ người dùng cho Admin Web đọc.
  /// Lỗi đồng bộ không được làm hỏng đăng nhập: chỉ ghi log rồi đi tiếp.
  Future<void> _syncUserProfile(User user) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = this.firestore ?? FirebaseFirestore.instance;
      final ref = firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid);
      final existing = await ref.get();
      final existingRole = existing.data()?['role'];
      final hasRole = existingRole is String && existingRole.trim().isNotEmpty;
      await ref.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'lastSignInAt': FieldValue.serverTimestamp(),
        // Mobile chỉ dành cho giảng viên; chỉ ghi khi chưa có để không hạ quyền admin.
        if (!hasRole) 'role': 'teacher',
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('AuthService user profile sync error: $error');
    }
  }

  /// Khởi tạo Google Sign-In đúng một lần cho cả vòng đời app.
  ///
  /// Future đã lỗi vẫn được giữ lại: plugin web đánh dấu "đã init" trước khi
  /// ném lỗi, nên gọi init() lần nữa sẽ ném "init() has already been called"
  /// và che mất lỗi gốc.
  /// Khởi tạo Google Sign-In nếu chưa khởi tạo.
  Future<void> ensureGoogleInitialized() => _ensureGoogleInitialized();

  Future<void> _ensureGoogleInitialized() async {
    final initialization = _googleInitialization ??= _initializeGoogle();
    await initialization;
  }

  Future<void> _initializeGoogle() {
    final init = resolveGoogleSignInInit(
      isWeb: kIsWeb,
      webClientId: DefaultFirebaseOptions.googleSignInWebClientId,
    );
    return _googleInitializer(
      clientId: init.clientId,
      serverClientId: init.serverClientId,
    );
  }
}
